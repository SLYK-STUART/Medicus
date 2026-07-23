const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

exports.createAppointment = onCall(async (request) => {
  const caller = request.auth;
  if (!caller) throw new HttpsError("unauthenticated", "Must be signed in.");

  const {patientId, hospitalId, departmentId, doctorId, scheduledDate, scheduledTimeSlot} =
    request.data ?? {};

  if (!hospitalId || !departmentId || !scheduledDate) {
    throw new HttpsError("invalid-argument", "hospitalId, departmentId, and scheduledDate are required.");
  }

  const callerRole = caller.token.role;
  const callerHospitalId = caller.token.hospitalId ?? null;

  let resolvedPatientId;
  if (callerRole === "patient") {
    resolvedPatientId = caller.uid;
  } else if (callerRole === "receptionist") {
    if (callerHospitalId !== hospitalId) {
      throw new HttpsError("permission-denied", "Cannot book outside your own hospital.");
    }
    if (!patientId) {
      throw new HttpsError("invalid-argument", "patientId is required when a receptionist books on a patient's behalf.");
    }
    resolvedPatientId = patientId;
  } else {
    throw new HttpsError("permission-denied", "Only a patient or a receptionist may create an appointment.");
  }

  const db = getFirestore();

  const patientUserSnap = await db.collection("users").doc(resolvedPatientId).get();
  const patientData = patientUserSnap.exists ? patientUserSnap.data() : {};
  const patientName = patientData.displayName ?? "Unknown";
  const patientPhoneNumber = patientData.phoneNumber ?? null;

  const counterId = `${hospitalId}_${departmentId}_${scheduledDate}`;
  const counterRef = db.collection("counters").doc(counterId);
  const appointmentRef = db.collection("appointments").doc();

  try {
    const tokenNumber = await db.runTransaction(async (tx) => {
      // Capacity check — only when a slot was actually requested. Walk-in,
      // Priority Check-In, referral, and follow-up bookings never pass
      // scheduledTimeSlot, so they're entirely unaffected by this block.
      if (scheduledTimeSlot) {
        const deptSnap = await tx.get(db.collection("departments").doc(departmentId));
        if (!deptSnap.exists) {
          throw new HttpsError("not-found", "Department not found.");
        }
        const capacity = deptSnap.data().slotCapacity ?? 5;

        const existingSnap = await tx.get(
            db.collection("appointments")
                .where("hospitalId", "==", hospitalId)
                .where("departmentId", "==", departmentId)
                .where("scheduledDate", "==", scheduledDate)
                .where("scheduledTimeSlot", "==", scheduledTimeSlot)
                .where("status", "in", ["booked", "checked_in"]),
        );
        if (existingSnap.size >= capacity) {
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

      tx.set(appointmentRef, {
        patientId: resolvedPatientId,
        patientName,
        patientPhoneNumber,
        hospitalId,
        departmentId,
        doctorId: doctorId ?? null,
        scheduledDate,
        scheduledTimeSlot: scheduledTimeSlot ?? null,
        tokenNumber: nextToken,
        status: "booked",
        visitId: null,
        isRecurring: false,
        recurringParentId: null,
        bookedBy: caller.uid,
        source: callerRole === "patient" ? "patient_booking" : "receptionist_booking",
        createdAt: FieldValue.serverTimestamp(),
      });

      return nextToken;
    });

    logger.info(`createAppointment: ${appointmentRef.id} booked, token=${tokenNumber}, patient=${resolvedPatientId} (${patientName}), slot=${scheduledTimeSlot ?? "none"}`);
    return {appointmentId: appointmentRef.id, tokenNumber};
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error("createAppointment: transaction failed", err);
    throw new HttpsError("internal", "Failed to book appointment.");
  }
});
