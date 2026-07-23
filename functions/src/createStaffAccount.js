const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const ALLOWED_CREATABLE_ROLES = ["hospital_admin", "receptionist", "doctor"];

exports.createStaffAccount = onCall(async (request) => {
  const callerAuth = request.auth;
  if (!callerAuth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const callerRole = callerAuth.token.role;
  const callerHospitalId = callerAuth.token.hospitalId ?? null;

  const {email, password, displayName, role, hospitalId, departmentId, avgConsultationMinutes, roomNumber} = request.data ?? {};

  if (!email || !password || !role) {
    throw new HttpsError("invalid-argument", "email, password, and role are required.");
  }
  if (!ALLOWED_CREATABLE_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", `role must be one of ${ALLOWED_CREATABLE_ROLES.join(", ")}.`);
  }
  if (typeof password !== "string" || password.length < 6) {
    throw new HttpsError("invalid-argument", "password must be at least 6 characters.");
  }
  if (role === "doctor" && !departmentId) {
    throw new HttpsError("invalid-argument", "departmentId is required when creating a doctor.");
  }

  let targetHospitalId;

  if (callerRole === "super_admin") {
    if (role !== "hospital_admin") {
      throw new HttpsError("permission-denied", "super_admin may only create hospital_admin accounts here.");
    }
    if (!hospitalId) {
      throw new HttpsError("invalid-argument", "hospitalId is required when creating a hospital_admin.");
    }
    targetHospitalId = hospitalId;
  } else if (callerRole === "hospital_admin") {
    if (!["receptionist", "doctor"].includes(role)) {
      throw new HttpsError("permission-denied", "hospital_admin may only create receptionist or doctor accounts.");
    }
    if (!callerHospitalId) {
      throw new HttpsError("failed-precondition", "Caller has no hospitalId on their own token.");
    }
    targetHospitalId = callerHospitalId;
  } else {
    throw new HttpsError("permission-denied", "Only super_admin or hospital_admin may create staff accounts.");
  }

  const auth = getAuth();
  const db = getFirestore();

  let userRecord;
  try {
    userRecord = await auth.createUser({
      email,
      password,
      displayName: displayName || undefined,
      emailVerified: false,
    });
  } catch (err) {
    logger.error("createStaffAccount: auth.createUser failed", err);
    if (err.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "An account with this email already exists.");
    }
    throw new HttpsError("internal", "Failed to create the account.");
  }

  try {
    await auth.setCustomUserClaims(userRecord.uid, {
      role,
      hospitalId: targetHospitalId,
    });

    await db.collection("users").doc(userRecord.uid).set({
      uid: userRecord.uid,
      email,
      displayName: displayName || null,
      role,
      hospitalId: targetHospitalId,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: callerAuth.uid,
    });

    if (role === "doctor") {
      // Denormalized displayName/hospitalId/departmentId kept here too so
      // booking screens can list doctors without a join back to users/.
      await db.collection("doctors").doc(userRecord.uid).set({
        uid: userRecord.uid,
        displayName: displayName || null,
        hospitalId: targetHospitalId,
        departmentId,
        roomNumber: roomNumber || null,
        avgConsultationMinutes: avgConsultationMinutes ?? 15, // SRS 7 fallback default until real history exists
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  } catch (err) {
    logger.error("createStaffAccount: post-creation setup failed, rolling back auth user", err);
    await auth.deleteUser(userRecord.uid).catch((cleanupErr) => {
      logger.error("createStaffAccount: rollback deleteUser also failed", cleanupErr);
    });
    throw new HttpsError("internal", "Account setup failed; the account was not created.");
  }

  logger.info(`createStaffAccount: ${callerAuth.uid} created ${role} ${userRecord.uid} (hospitalId=${targetHospitalId})`);

  return {uid: userRecord.uid, email, role, hospitalId: targetHospitalId};
});
