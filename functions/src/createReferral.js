const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

exports.createReferral = onCall(async (request) => {
  const caller = request.auth;
  if (!caller || caller.token.role !== "doctor") {
    throw new HttpsError("permission-denied", "Only a doctor may refer a patient to another department.");
  }

  const {originAppointmentId, targetDepartmentId} = request.data ?? {};
  if (!originAppointmentId || !targetDepartmentId) {
    throw new HttpsError("invalid-argument", "originAppointmentId and targetDepartmentId are required.");
  }

  const db = getFirestore();
  const callerHospitalId = caller.token.hospitalId ?? null;

  const originRef = db.collection("appointments").doc(originAppointmentId);
  const originSnap = await originRef.get();
  if (!originSnap.exists) {
    throw new HttpsError("not-found", "Original appointment not found.");
  }
  const origin = originSnap.data();

  if (origin.hospitalId !== callerHospitalId) {
    throw new HttpsError("permission-denied", "Cannot refer outside your own hospital.");
  }
  if (origin.departmentId === targetDepartmentId) {
    throw new HttpsError("invalid-argument", "Target department must differ from the current one.");
  }

  // Reuse the visit if one already exists for this patient's journey today;
  // otherwise this is the first referral in the chain — create it now and
  // stamp it back onto the origin appointment.
  let visitId = origin.visitId ?? null;
  if (!visitId) {
    const visitRef = db.collection("visits").doc();
    visitId = visitRef.id;
    await visitRef.set({
      patientId: origin.patientId,
      hospitalId: origin.hospitalId,
      originAppointmentId,
      createdAt: FieldValue.serverTimestamp(),
    });
    await originRef.update({visitId});
  }

  const today = origin.scheduledDate; // referral happens same-day as the visit it's part of
  const counterId = `${origin.hospitalId}_${targetDepartmentId}_${today}`;
  const counterRef = db.collection("counters").doc(counterId);
  const targetAppointmentRef = db.collection("appointments").doc();

  try {
    const tokenNumber = await db.runTransaction(async (tx) => {
      const counterSnap = await tx.get(counterRef);
      const lastToken = counterSnap.exists ? (counterSnap.data().lastToken ?? 0) : 0;
      const nextToken = lastToken + 1;

      tx.set(
          counterRef,
          {hospitalId: origin.hospitalId, departmentId: targetDepartmentId, date: today, lastToken: nextToken, updatedAt: FieldValue.serverTimestamp()},
          {merge: true},
      );

      tx.set(targetAppointmentRef, {
        patientId: origin.patientId,
        patientName: origin.patientName,
        patientPhoneNumber: origin.patientPhoneNumber,
        hospitalId: origin.hospitalId,
        departmentId: targetDepartmentId,
        doctorId: null,
        scheduledDate: today,
        scheduledTimeSlot: null,
        tokenNumber: nextToken,
        status: "checked_in",
        visitId,
        isRecurring: false,
        recurringParentId: null,
        bookedBy: caller.uid,
        source: "referral",
        createdAt: FieldValue.serverTimestamp(),
      });

      return nextToken;
    });

    // Queue entry written after the transaction commits, same as a normal
    // check-in — not folded into the transaction above since it's a
    // different collection/path shape (queue_entries is nested by
    // hospital/date/department, appointments/counters are flat).
    const queueEntryRef = db
        .collection("queue_entries")
        .doc(origin.hospitalId)
        .collection(today)
        .doc(targetDepartmentId)
        .collection("entries")
        .doc();

    await queueEntryRef.set({
      appointmentId: targetAppointmentRef.id,
      patientId: origin.patientId,
      doctorId: "",
      tokenNumber,
      checkedInAt: FieldValue.serverTimestamp(),
      priority: "normal",
      priorityRank: 2,
      status: "waiting",
      lastNotifiedThreshold: "none",
    });

    logger.info(`createReferral: ${caller.uid} referred patient ${origin.patientId} from ${origin.departmentId} to ${targetDepartmentId}, visit ${visitId}, token #${tokenNumber}`);
    return {appointmentId: targetAppointmentRef.id, tokenNumber, visitId};
  } catch (err) {
    logger.error("createReferral: failed", err);
    throw new HttpsError("internal", "Failed to create referral.");
  }
});
