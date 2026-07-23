const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const ROLLING_WINDOW_SIZE = 30;
const FALLBACK_MINUTES = 15;

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
}

exports.onConsultationCompleted = onDocumentWritten(
    "queue_entries/{hospitalId}/{date}/{departmentId}/entries/{entryId}",
    async (event) => {
      const before = event.data?.before?.data();
      const after = event.data?.after?.data();

      if (!after || after.status !== "completed" || before?.status === "completed") {
        return;
      }

      const {doctorId, consultationStartedAt, consultationCompletedAt, totalPausedMs} = after;
      if (!doctorId || !consultationStartedAt || !consultationCompletedAt) {
        logger.warn("onConsultationCompleted: missing doctorId or timestamps, skipping", {entryId: event.params.entryId});
        return;
      }

      const rawDurationMs = consultationCompletedAt.toMillis() - consultationStartedAt.toMillis();
      const durationMs = rawDurationMs - (totalPausedMs ?? 0); // exclude time spent paused for an emergency
      const durationMinutes = durationMs / 60000;

      if (durationMinutes <= 0 || durationMinutes > 240) {
        logger.warn(`onConsultationCompleted: implausible duration ${durationMinutes}min, skipping`, {doctorId});
        return;
      }

      const db = getFirestore();
      const doctorRef = db.collection("doctors").doc(doctorId);

      try {
        await db.runTransaction(async (tx) => {
          const doctorSnap = await tx.get(doctorRef);
          if (!doctorSnap.exists) return;

          const existing = doctorSnap.data().recentConsultationDurations ?? [];
          const updated = [...existing, durationMinutes].slice(-ROLLING_WINDOW_SIZE);
          const newAvg = updated.length > 0 ? Math.round(median(updated)) : FALLBACK_MINUTES;

          tx.update(doctorRef, {
            recentConsultationDurations: updated,
            avgConsultationMinutes: newAvg,
          });
        });

        logger.info(`onConsultationCompleted: doctor ${doctorId} avg updated from a ${durationMinutes.toFixed(1)}min consultation (paused time excluded: ${totalPausedMs ?? 0}ms)`);
      } catch (err) {
        logger.error("onConsultationCompleted: failed to update doctor average", err);
      }
    },
);
