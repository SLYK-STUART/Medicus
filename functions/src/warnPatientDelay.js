const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");

exports.warnPatientDelay = onCall(async (request) => {
  const caller = request.auth;
  if (!caller || caller.token.role !== "doctor") {
    throw new HttpsError("permission-denied", "Only a doctor may issue a delay warning.");
  }

  const {hospitalId, date, departmentId, entryId} = request.data ?? {};
  if (!hospitalId || !date || !departmentId || !entryId) {
    throw new HttpsError("invalid-argument", "hospitalId, date, departmentId, and entryId are required.");
  }

  const db = getFirestore();
  const entryRef = db
      .collection("queue_entries")
      .doc(hospitalId)
      .collection(date)
      .doc(departmentId)
      .collection("entries")
      .doc(entryId);

  const entrySnap = await entryRef.get();
  if (!entrySnap.exists) throw new HttpsError("not-found", "Queue entry not found.");
  const entry = entrySnap.data();

  if (entry.doctorId !== caller.uid) {
    throw new HttpsError("permission-denied", "This patient is not assigned to you.");
  }
  if (entry.status !== "called") {
    throw new HttpsError("failed-precondition", "Can only warn a patient who has been called and hasn't arrived yet.");
  }

  const hospitalSnap = await db.collection("hospitals").doc(hospitalId).get();
  const graceMinutes = hospitalSnap.exists ? (hospitalSnap.data().noShowGraceMinutes ?? 5) : 5;

  const now = Date.now();
  const graceDeadline = Timestamp.fromMillis(now + graceMinutes * 60000);

  await entryRef.update({
    warnedAt: FieldValue.serverTimestamp(),
    graceDeadline,
    graceMinutes,
  });

  // Notification dispatch — small local version rather than importing
  // queueNotifications.js's dispatchNotification, since this is a
  // doctor-triggered event, not a queue-write-triggered one, and pulling
  // in that file's trigger-specific context isn't worth the coupling for
  // one shared helper. Same three channels (in-app, SMS, push) though.
  const message = `You haven't checked in for your consultation yet. If you don't report within ${graceMinutes} minutes, you will be skipped and will need to check in again to rejoin the queue.`;

  await db.collection("notifications").add({
    userId: entry.patientId,
    type: "delay_warning",
    message,
    hospitalId,
    appointmentId: entry.appointmentId,
    queueEntryId: entryId,
    read: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  const patientUserSnap = await db.collection("users").doc(entry.patientId).get();
  const patientData = patientUserSnap.exists ? patientUserSnap.data() : {};

  if (patientData.phoneNumber) {
    await db.collection("sms_emulator").add({
      phoneNumber: patientData.phoneNumber,
      message,
      relatedUserId: entry.patientId,
      relatedAppointmentId: entry.appointmentId,
      status: "sent",
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  if (patientData.fcmToken) {
    try {
      await getMessaging().send({
        token: patientData.fcmToken,
        notification: {title: "Hospital Queue", body: message},
        data: {type: "delay_warning", appointmentId: entry.appointmentId ?? "", queueEntryId: entryId},
      });
    } catch (err) {
      logger.warn(`warnPatientDelay: FCM send failed for ${entry.patientId}`, err.message);
    }
  }

  logger.info(`warnPatientDelay: doctor ${caller.uid} warned entry ${entryId}, grace ${graceMinutes}min`);
  return {graceMinutes, graceDeadlineMillis: now + graceMinutes * 60000};
});
