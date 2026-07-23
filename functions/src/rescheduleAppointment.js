const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

exports.rescheduleAppointment = onCall(async (request) => {
  const caller = request.auth;
  if (!caller || caller.token.role !== "patient") {
    throw new HttpsError("permission-denied", "Only a patient may reschedule their own appointment.");
  }

  const {appointmentId, hospitalId, departmentId, scheduledDate, scheduledTimeSlot} = request.data ?? {};
  if (!appointmentId || !hospitalId || !departmentId || !scheduledDate) {
    throw new HttpsError("invalid-argument", "appointmentId, hospitalId, departmentId, and scheduledDate are required.");
  }

  const db = getFirestore();
  const apptRef = db.collection("appointments").doc(appointmentId);
  const apptSnap = await apptRef.get();
  if (!apptSnap.exists) throw new HttpsError("not-found", "Appointment not found.");
  const appt = apptSnap.data();

  if (appt.patientId !== caller.uid) {
    throw new HttpsError("permission-denied", "You may only reschedule your own appointments.");
  }
  if (appt.status !== "booked") {
    throw new HttpsError("failed-precondition", "Only a booked (not yet checked in) appointment can be rescheduled.");
  }

  const counterId = `${hospitalId}_${departmentId}_${scheduledDate}`;
  const counterRef = db.collection("counters").doc(counterId);

  try {
    const tokenNumber = await db.runTransaction(async (tx) => {
      if (scheduledTimeSlot) {
        const deptSnap = await tx.get(db.collection("departments").doc(departmentId));
        if (!deptSnap.exists) throw new HttpsError("not-found", "Department not found.");
        const capacity = deptSnap.data().slotCapacity ?? 5;

        const existingSnap = await tx.get(
            db.collection("appointments")
                .where("hospitalId", "==", hospitalId)
                .where("departmentId", "==", departmentId)
                .where("scheduledDate", "==", scheduledDate)
                .where("scheduledTimeSlot", "==", scheduledTimeSlot)
                .where("status", "in", ["booked", "checked_in"]),
        );
        // Exclude this appointment's own current slot-count contribution —
        // relevant when rescheduling within the SAME slot it already
        // occupies (e.g. just re-confirming), so it doesn't count against
        // its own capacity.
        const occupiedCount = existingSnap.docs.filter((d) => d.id !== appointmentId).length;
        if (occupiedCount >= capacity) {
          throw new HttpsError("resource-exhausted", "This time slot is fully booked. Please choose another.");
        }
      }

      const counterSnap = await tx.get(counterRef);
      const lastToken = counterSnap.exists ? (counterSnap.data().lastToken ?? 0) : 0;
      const nextToken = lastToken + 1;

      tx.set(
          counterRef,
          {hospitalId, departmentId, date: scheduledDate, lastToken: nextToken, updatedAt: FieldValue.serverTimestamp()},
          {merge: true},
      );

      // Same appointment doc, updated in place — identity (id, QR code,
      // history) is preserved. doctorId reset to null: a 'booked'
      // appointment always has a null doctorId anyway (doctor assignment
      // happens at call-time, not booking-time — see progress notes),
      // this is just explicit rather than assumed.
      tx.update(apptRef, {
        hospitalId,
        departmentId,
        doctorId: null,
        scheduledDate,
        scheduledTimeSlot: scheduledTimeSlot ?? null,
        tokenNumber: nextToken,
        rescheduledAt: FieldValue.serverTimestamp(),
      });

      return nextToken;
    });

    logger.info(`rescheduleAppointment: ${appointmentId} moved to ${hospitalId}/${departmentId}/${scheduledDate}, new token #${tokenNumber}`);
    return {appointmentId, tokenNumber};
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error("rescheduleAppointment: failed", err);
    throw new HttpsError("internal", "Failed to reschedule appointment.");
  }
});
