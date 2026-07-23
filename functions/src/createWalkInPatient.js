const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

exports.createWalkInPatient = onCall(async (request) => {
  const caller = request.auth;
  if (!caller || caller.token.role !== "receptionist") {
    throw new HttpsError("permission-denied", "Only a receptionist may create a walk-in patient record.");
  }

  const {displayName, phoneNumber, email} = request.data ?? {};
  if (!displayName) {
    throw new HttpsError("invalid-argument", "displayName is required.");
  }

  const auth = getAuth();
  const db = getFirestore();

  let userRecord;
  try {
    userRecord = await auth.createUser({
      displayName,
      ...(phoneNumber ? {phoneNumber} : {}),
      ...(email ? {email} : {}),
    });
  } catch (err) {
    logger.error("createWalkInPatient: auth.createUser failed", err);
    if (err.code === "auth/phone-number-already-exists" || err.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "A patient with this phone/email already exists.");
    }
    throw new HttpsError("internal", "Failed to create patient record.");
  }

  try {
    await auth.setCustomUserClaims(userRecord.uid, {role: "patient", hospitalId: null});
    await db.collection("users").doc(userRecord.uid).set({
      uid: userRecord.uid,
      email: email ?? null,
      phoneNumber: phoneNumber ?? null,
      displayName,
      role: "patient",
      hospitalId: null,
      hasNoLoginCredentials: !email,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: caller.uid,
    });
  } catch (err) {
    logger.error("createWalkInPatient: post-creation setup failed, rolling back", err);
    await auth.deleteUser(userRecord.uid).catch((e) => logger.error("rollback failed", e));
    throw new HttpsError("internal", "Patient setup failed; record was not created.");
  }

  // Every walk-in creation notifies the creating receptionist — content
  // differs based on whether a phone number was captured, but a
  // notification fires either way now, not just the no-phone case.
  const message = phoneNumber ?
    `${displayName} was added successfully. SMS updates will be sent to ${phoneNumber}.` :
    `${displayName} was added without a phone number — no SMS updates will be sent for their visit.`;

  await db.collection("notifications").add({
    userId: caller.uid,
    type: phoneNumber ? "walkin_created" : "walkin_no_phone",
    message,
    hospitalId: caller.token.hospitalId ?? null,
    appointmentId: null,
    queueEntryId: null,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {uid: userRecord.uid};
});
