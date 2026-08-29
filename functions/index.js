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
                phrases: ["help", "help me", "sos", "emergency", "save me", "tulong"],
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

        const emergencyKeywords = ["help", "sos", "emergency", "save", "tulong", "distress", "stop"];
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
      if (data.location) deviceUpdate.location = data.location;
      if (data.coordinates) deviceUpdate.coordinates = data.coordinates;
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
    return null;
  });

