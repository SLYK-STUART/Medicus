const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

function addDays(dateStr, days) {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10); // yyyy-MM-dd
}

exports.createFollowUpAppointment = onCall(async (request) => {
  const caller = request.auth;
  if (!caller || caller.token.role !== "doctor") {
    throw new HttpsError("permission-denied", "Only a doctor may schedule a follow-up.");
  }

  const {originAppointmentId, daysFromNow} = request.data ?? {};
  if (!originAppointmentId || !daysFromNow || daysFromNow < 1) {
    throw new HttpsError("invalid-argument", "originAppointmentId and a positive daysFromNow are required.");
  }

  const db = getFirestore();
  const originRef = db.collection("appointments").doc(originAppointmentId);
  const originSnap = await originRef.get();
  if (!originSnap.exists) {
    throw new HttpsError("not-found", "Original appointment not found.");
  }
  const origin = originSnap.data();

  if (origin.doctorId !== caller.uid) {
    throw new HttpsError("permission-denied", "You may only schedule a follow-up for a patient you personally saw.");
  }

  const today = new Date().toISOString().slice(0, 10);
  const scheduledDate = addDays(today, daysFromNow);

  const counterId = `${origin.hospitalId}_${origin.departmentId}_${scheduledDate}`;
  const counterRef = db.collection("counters").doc(counterId);
  const followUpRef = db.collection("appointments").doc();

  try {
    const tokenNumber = await db.runTransaction(async (tx) => {
      const counterSnap = await tx.get(counterRef);
      const lastToken = counterSnap.exists ? (counterSnap.data().lastToken ?? 0) : 0;
      const nextToken = lastToken + 1;

      tx.set(
          counterRef,
          {hospitalId: origin.hospitalId, departmentId: origin.departmentId, date: scheduledDate, lastToken: nextToken, updatedAt: FieldValue.serverTimestamp()},
          {merge: true},
      );

      tx.set(followUpRef, {
        patientId: origin.patientId,
        patientName: origin.patientName,
        patientPhoneNumber: origin.patientPhoneNumber,
        hospitalId: origin.hospitalId,
        departmentId: origin.departmentId,
        doctorId: origin.doctorId,
        scheduledDate,
        scheduledTimeSlot: null,
        tokenNumber: nextToken,
        status: "booked",
        visitId: null,
        isRecurring: true,
        recurringParentId: originAppointmentId,
        bookedBy: caller.uid,
        source: "follow_up",
        createdAt: FieldValue.serverTimestamp(),
      });

      return nextToken;
    });

    logger.info(`createFollowUpAppointment: doctor ${caller.uid} scheduled follow-up ${followUpRef.id} for patient ${origin.patientId} on ${scheduledDate}, token #${tokenNumber}`);
    return {appointmentId: followUpRef.id, scheduledDate, tokenNumber};
  } catch (err) {
    logger.error("createFollowUpAppointment: failed", err);
    throw new HttpsError("internal", "Failed to schedule follow-up.");
  }
});
