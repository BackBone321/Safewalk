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
