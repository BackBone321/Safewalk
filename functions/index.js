const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

exports.updateUserPassword = functions.https.onCall(async (data, context) => {
  // Ensure the caller is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "The function must be called while authenticated."
    );
  }

  // Verify the caller is an admin by checking Firestore
  const callerUid = context.auth.uid;
  const userDoc = await admin
    .firestore()
    .collection("users")
    .doc(callerUid)
    .get();

  if (!userDoc.exists || userDoc.data().role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Only administrators can change passwords."
    );
  }

  const { uid, newPassword } = data;

  if (!uid || typeof uid !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid 'uid' string is required."
    );
  }

  if (!newPassword || typeof newPassword !== "string" || newPassword.length < 6) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid 'newPassword' of at least 6 characters is required."
    );
  }

  try {
    await admin.auth().updateUser(uid, { password: newPassword });
    return { success: true, message: "Password updated successfully." };
  } catch (error) {
    console.error("Error updating user password:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to update user password: " + error.message
    );
  }
});

// Helper function to query Speech-to-Text API and transcribe audio clip
async function verifyVoiceDistressSpeech(base64Audio) {
  if (!base64Audio || typeof base64Audio !== "string") {
    return { isDistress: true, transcript: "(No audio content)", confidence: 0 };
  }

  let cleanBase64 = base64Audio;
  if (cleanBase64.includes("base64,")) {
    cleanBase64 = cleanBase64.split("base64,")[1];
  }

  // Strip WAV 44-byte header if present to extract raw 16-bit PCM (LINEAR16) payload
  let pcmContent = cleanBase64;
  try {
    const rawBuffer = Buffer.from(cleanBase64, "base64");
    if (rawBuffer.length > 44 && rawBuffer.toString("ascii", 0, 4) === "RIFF") {
      pcmContent = rawBuffer.subarray(44).toString("base64");
    }
  } catch (e) {
    console.error("WAV header strip error:", e);
  }

  const apiKey = process.env.FIREBASE_API_KEY || process.env.SPEECH_API_KEY;

  if (apiKey) {
    try {
      const response = await fetch(`https://speech.googleapis.com/v1/speech:recognize?key=${apiKey}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          config: {
            encoding: "LINEAR16",
            sampleRateHertz: 8000,
            languageCode: "en-US",
            alternativeLanguageCodes: ["tl-PH"],
            speechContexts: [
              {
                phrases: ["help", "help me", "sos", "emergency", "save me", "tulong", "tabang"],
                boost: 20.0
              }
            ]
          },
          audio: {
            content: pcmContent
          }
        })
      });

      if (response.ok) {
        const resultJson = await response.json();
        let fullTranscript = "";
        let maxConfidence = 0;

        if (resultJson.results && resultJson.results.length > 0) {
          for (const res of resultJson.results) {
            if (res.alternatives && res.alternatives.length > 0) {
              const alt = res.alternatives[0];
              fullTranscript += " " + (alt.transcript || "");
              if (alt.confidence > maxConfidence) {
                maxConfidence = alt.confidence;
              }
            }
          }
        }

        fullTranscript = fullTranscript.trim().toLowerCase();
        console.log(`[SPEECH AI] Transcription: "${fullTranscript}" (Confidence: ${maxConfidence})`);

        const emergencyKeywords = ["help", "sos", "emergency", "save", "tulong", "tabang", "distress", "stop"];
        const containsDistress = emergencyKeywords.some(word => fullTranscript.includes(word));

        return {
          isDistress: containsDistress,
          transcript: fullTranscript || "(No text recognized)",
          confidence: maxConfidence
        };
      } else {
        const errText = await response.text();
        console.warn(`Speech API non-200 response (${response.status}): ${errText}`);
      }
    } catch (err) {
      console.error("Error calling Cloud Speech-to-Text API:", err);
    }
  }

  // Default fallback if API Key is not set or network unreachable
  return {
    isDistress: true,
    transcript: "(Speech AI API lock-in active - pending API key)",
    confidence: 1.0
  };
}

function normalizeGuardianPhone(raw) {
  const cleaned = String(raw || "").trim().replace(/[\s\-().]/g, "");
  if (!cleaned) return "";
  if (cleaned.startsWith("+")) return cleaned;
  if (cleaned.startsWith("09") && cleaned.length === 11) {
    return `+63${cleaned.substring(1)}`;
  }
  if (cleaned.startsWith("639") && cleaned.length === 12) {
    return `+${cleaned}`;
  }
  if (cleaned.startsWith("9") && cleaned.length === 10) {
    return `+63${cleaned}`;
  }
  return cleaned;
}

function isValidGuardianPhone(raw) {
  return /^\+?[0-9]{10,15}$/.test(normalizeGuardianPhone(raw));
}

function parsePhoneCsv(value) {
  return String(value || "")
    .split(/[,;]/)
    .map((part) => part.trim())
    .filter((part) => part.length > 0);
}

async function resolveGuardianAudience(studentUid, alertData) {
  const db = admin.firestore();
  const contacts = [];
  const phones = [];
  const seenPhones = new Set();
  const recipientUids = [];
  const seenUids = new Set();
  let primaryParentUid = String((alertData && alertData.parentUid) || "").trim();
  let primaryParentPhone = String((alertData && alertData.parentPhoneNumber) || "").trim();

  const addPhone = (raw) => {
    const normalized = normalizeGuardianPhone(raw);
    if (!isValidGuardianPhone(raw) || seenPhones.has(normalized) || phones.length >= 12) {
      return;
    }
    seenPhones.add(normalized);
    phones.push(String(raw).trim());
  };
  const addUid = (uid) => {
    const cleaned = String(uid || "").trim();
    if (!cleaned || seenUids.has(cleaned)) return;
    seenUids.add(cleaned);
    recipientUids.push(cleaned);
  };

  addUid(primaryParentUid);
  addPhone(primaryParentPhone);
  parsePhoneCsv(alertData && alertData.guardianPhonesCsv).forEach(addPhone);
  if (Array.isArray(alertData && alertData.guardianPhones)) {
    alertData.guardianPhones.forEach(addPhone);
  }
  if (Array.isArray(alertData && alertData.recipientUids)) {
    alertData.recipientUids.forEach(addUid);
  }

  if (studentUid) {
    const guardianSnap = await db.collection("users").doc(studentUid).collection("guardians").get();
    guardianSnap.forEach((doc) => {
      const data = doc.data() || {};
      const phone = String(data.phoneNumber || "").trim();
      contacts.push({
        id: doc.id,
        name: String(data.name || "Guardian"),
        phoneNumber: phone,
        phoneNormalized: normalizeGuardianPhone(phone),
        relationship: String(data.relationship || "Guardian"),
        source: "guardian",
      });
      addPhone(phone);
    });

    const linkSnap = await db.collection("parent_student_links")
      .where("studentUid", "==", studentUid)
      .limit(50)
      .get();
    linkSnap.forEach((doc) => {
      const data = doc.data() || {};
      const status = String(data.status || "accepted").toLowerCase();
      if (status !== "accepted") return;
      const parentUid = String(data.parentUid || "").trim();
      const parentPhone = String(data.parentPhone || "").trim();
      const parentName = String(data.parentName || "Parent").trim() || "Parent";
      addUid(parentUid);
      if (!primaryParentUid && parentUid) {
        primaryParentUid = parentUid;
        primaryParentPhone = parentPhone;
      }
      contacts.push({
        id: `parent:${parentUid}`,
        name: parentName,
        phoneNumber: parentPhone,
        phoneNormalized: normalizeGuardianPhone(parentPhone),
        relationship: "Parent",
        parentUid,
        source: "parent_link",
      });
      addPhone(parentPhone);
    });
  }

  return {
    contacts,
    phones,
    phonesCsv: phones.join(","),
    recipientUids,
    primaryParentUid,
    primaryParentPhone,
  };
}

async function logGuardianSms(phone, message, status, extra) {
  await admin.firestore().collection("sms_logs").add({
    phoneNumber: phone,
    message,
    status,
    error: (extra && extra.error) || "",
    providerStatusCode: extra && extra.providerStatusCode ? extra.providerStatusCode : null,
    providerResponse: (extra && extra.providerResponse) || "",
    triggeredBy: "emergency_broadcast",
    alertId: (extra && extra.alertId) || "",
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

async function sendGuardianSmsBatch(phones, message, alertId) {
  const endpoint = process.env.SMS_GATEWAY_ENDPOINT || "";
  const apiKey = process.env.SMS_GATEWAY_API_KEY || "";
  const sender = process.env.SMS_GATEWAY_SENDER || "SAFEWALK";
  if (!endpoint || !apiKey) {
    for (const phone of phones) {
      await logGuardianSms(phone, message, "not_configured", {
        alertId,
        error: "SMS gateway configuration is missing.",
      });
    }
    return {status: "not_configured", sent: 0, failed: phones.length};
  }

  let sent = 0;
  let failed = 0;
  for (const phone of phones) {
    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({to: phone, message, sender}),
      });
      const body = await response.text();
      const success = response.status >= 200 && response.status < 300;
      await logGuardianSms(phone, message, success ? "sent" : "failed", {
        alertId,
        providerStatusCode: response.status,
        providerResponse: body,
        error: success ? "" : `SMS send failed (${response.status})`,
      });
      if (success) sent += 1;
      else failed += 1;
    } catch (error) {
      failed += 1;
      await logGuardianSms(phone, message, "failed", {
        alertId,
        error: error.message || String(error),
      });
    }
  }
  return {
    status: sent === 0 ? "failed" : failed === 0 ? "sent" : "partial",
    sent,
    failed,
  };
}

async function syncGuardianCsvToDevices(studentUid, deviceId, phonesCsv, primary) {
  const db = admin.firestore();
  const patch = {
    guardianPhonesCsv: phonesCsv,
    guardiansUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (primary.primaryParentUid) patch.parentUid = primary.primaryParentUid;
  if (primary.primaryParentPhone) patch.parentPhoneNumber = primary.primaryParentPhone;

  const refs = new Map();
  if (studentUid) {
    const snap = await db.collection("devices").where("studentUid", "==", studentUid).get();
    snap.forEach((doc) => refs.set(doc.id, doc.ref));
  }
  if (deviceId) {
    const directSnap = await db.collection("devices").doc(deviceId).get();
    if (directSnap.exists) refs.set(directSnap.id, directSnap.ref);
    const byField = await db.collection("devices").where("deviceId", "==", deviceId).limit(5).get();
    byField.forEach((doc) => refs.set(doc.id, doc.ref));
  }
  if (refs.size === 0) return;
  const batch = db.batch();
  refs.forEach((ref) => batch.set(ref, patch, {merge: true}));
  await batch.commit();
}

async function broadcastAlertToGuardians(snapshot, data, alertId) {
  const studentUid = String((data && (data.studentUid || data.uid)) || "").trim();
  const audience = await resolveGuardianAudience(studentUid, data || {});
  const patch = {
    guardianContacts: audience.contacts,
    guardianPhones: audience.phones,
    guardianPhonesCsv: audience.phonesCsv,
    recipientUids: audience.recipientUids,
    notifiedGuardianCount: audience.phones.length,
  };
  if (!data.parentUid && audience.primaryParentUid) {
    patch.parentUid = audience.primaryParentUid;
    patch.parentPhoneNumber = audience.primaryParentPhone;
  }

  const covered = new Set();
  const deviceAlreadySent = data.triggeredBy === "iot_device" && data.smsSubmissionStatus === "submitted";
  if (deviceAlreadySent) {
    const parentPhone = normalizeGuardianPhone(data.parentPhoneNumber);
    if (parentPhone) covered.add(parentPhone);
    parsePhoneCsv(data.guardianPhonesCsv).forEach((phone) => {
      const normalized = normalizeGuardianPhone(phone);
      if (normalized) covered.add(normalized);
    });
  }

  const phonesToSend = data.clientHandlesSms === true
    ? []
    : audience.phones.filter((phone) => !covered.has(normalizeGuardianPhone(phone)));

  if (data.clientHandlesSms === true) {
    await snapshot.ref.set(patch, {merge: true});
  } else if (phonesToSend.length === 0) {
    patch.broadcastStatus = deviceAlreadySent ? "device_sms" : "no_recipients";
    patch.broadcastAt = admin.firestore.FieldValue.serverTimestamp();
    await snapshot.ref.set(patch, {merge: true});
  } else {
    const studentName = String(data.fullName || "A SafeWalk student");
    const location = String(data.location || "location pending");
    const message = `EMERGENCY ALERT: ${studentName} needs help. Location: ${location}`;
    const result = await sendGuardianSmsBatch(phonesToSend, message, alertId);
    patch.broadcastStatus = deviceAlreadySent && result.status !== "sent"
      ? `device_sms_${result.status}`
      : result.status;
    patch.notifiedGuardianCount = (deviceAlreadySent ? audience.phones.length - phonesToSend.length : 0) + result.sent;
    patch.broadcastFailedCount = result.failed;
    patch.broadcastAt = admin.firestore.FieldValue.serverTimestamp();
    await snapshot.ref.set(patch, {merge: true});
  }

  await syncGuardianCsvToDevices(
    studentUid,
    String(data.deviceId || ""),
    audience.phonesCsv,
    audience
  );
}

// Automatically update device live location & run Speech AI verification when an emergency alert is triggered
exports.onEmergencyAlertCreated = functions.firestore
  .document("emergency_alerts/{alertId}")
  .onCreate(async (snapshot, context) => {
    const alertId = context.params.alertId;
    const data = snapshot.data();
    if (!data) return null;

    const deviceId = data.deviceId;
    const alertUpdate = {};

    // Run Speech AI verification for voice_help alerts containing audio Clips
    if (data.type === "voice_help" && data.audioClip) {
      console.log(`[SPEECH AI] Verifying 3-second audio clip for alert ${alertId}...`);

      const speechResult = await verifyVoiceDistressSpeech(data.audioClip);

      alertUpdate.speechVerified = speechResult.isDistress;
      alertUpdate.transcript = speechResult.transcript;
      alertUpdate.speechConfidence = speechResult.confidence;
      alertUpdate.verifiedAt = admin.firestore.FieldValue.serverTimestamp();

      if (speechResult.isDistress) {
        console.log(`[SPEECH AI VERIFIED SUCCESS] Recognized distress speech: "${speechResult.transcript}"`);
        alertUpdate.status = "active";
        alertUpdate.verificationMessage = `Verified distress keyword "${speechResult.transcript}" spoken.`;
      } else {
        console.log(`[SPEECH AI REJECTED] Non-distress speech detected ("${speechResult.transcript}"). Suppressing alert.`);
        alertUpdate.status = "cancelled_false_trigger";
        alertUpdate.verificationMessage = `Suppressed non-distress speech ("${speechResult.transcript}").`;
      }

      await snapshot.ref.update(alertUpdate);
    }

    const isAlertActive = (alertUpdate.status === "active" || data.status === "active" || data.type !== "voice_help");

    if (deviceId && isAlertActive) {
      const deviceUpdate = {};
      const coordLat = data.coordinates && typeof data.coordinates.latitude === "number"
        ? data.coordinates.latitude
        : (typeof data.latitude === "number" ? data.latitude : 0);
      const coordLng = data.coordinates && typeof data.coordinates.longitude === "number"
        ? data.coordinates.longitude
        : (typeof data.longitude === "number" ? data.longitude : 0);
      const hasValidAlertCoords =
        (Math.abs(coordLat) > 0.0001 || Math.abs(coordLng) > 0.0001) &&
        Math.abs(coordLat) <= 90 &&
        Math.abs(coordLng) <= 180;

      const sentByDevice =
        data.triggeredBy === "iot_device" || data.locationSource === "device_gps";
      if (hasValidAlertCoords && sentByDevice) {
        if (data.location && !String(data.location).startsWith("0.0000")) {
          deviceUpdate.location = data.location;
        }
        if (data.coordinates) {
          deviceUpdate.coordinates = data.coordinates;
        }
        deviceUpdate.latitude = coordLat;
        deviceUpdate.longitude = coordLng;
      } else if (!hasValidAlertCoords) {
        try {
          const devSnap = await admin.firestore().collection("devices").doc(deviceId).get();
          const devData = devSnap.exists ? devSnap.data() : null;
          const devCoords = devData && devData.coordinates;
          const devLat = devCoords && typeof devCoords.latitude === "number"
            ? devCoords.latitude
            : (devData && typeof devData.latitude === "number" ? devData.latitude : 0);
          const devLng = devCoords && typeof devCoords.longitude === "number"
            ? devCoords.longitude
            : (devData && typeof devData.longitude === "number" ? devData.longitude : 0);
          if (Math.abs(devLat) > 0.0001 || Math.abs(devLng) > 0.0001) {
            const fallbackLabel = `${devLat.toFixed(6)}, ${devLng.toFixed(6)}`;
            await snapshot.ref.set({
              coordinates: new admin.firestore.GeoPoint(devLat, devLng),
              location: fallbackLabel,
              latitude: devLat,
              longitude: devLng,
            }, { merge: true });
            console.log(`Backfilled alert ${alertId} with valid device coordinates: ${fallbackLabel}`);
          }
        } catch (backfillErr) {
          console.error(`Failed to backfill alert ${alertId} from device ${deviceId}:`, backfillErr);
        }
      }
      if (data.type === "voice_help") deviceUpdate.lastVoiceAlertAt = admin.firestore.FieldValue.serverTimestamp();

      if (Object.keys(deviceUpdate).length > 0) {
        try {
          await admin
            .firestore()
            .collection("devices")
            .doc(deviceId)
            .update(deviceUpdate);
          console.log(`Successfully updated location/coordinates for device: ${deviceId}`);
        } catch (error) {
          console.error(`Failed to update device ${deviceId}:`, error);
        }
      }
    }
    if (alertUpdate.status !== "cancelled_false_trigger") {
      try {
        await broadcastAlertToGuardians(snapshot, data, alertId);
      } catch (broadcastErr) {
        console.error(`Guardian broadcast failed for ${alertId}:`, broadcastErr);
      }
    }
    return null;
  });

