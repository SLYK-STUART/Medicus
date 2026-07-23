const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

exports.callNextPatient = onCall(async (request) => {
  const caller = request.auth;
  if (!caller || caller.token.role !== "doctor") {
    throw new HttpsError("permission-denied", "Only a doctor may call the next patient.");
  }

  const {hospitalId, date} = request.data ?? {};
  if (!hospitalId || !date) {
    throw new HttpsError("invalid-argument", "hospitalId and date are required.");
  }

  const db = getFirestore();

  const doctorSnap = await db.collection("doctors").doc(caller.uid).get();
  if (!doctorSnap.exists) {
    throw new HttpsError("failed-precondition", "No doctor profile found for this account.");
  }
  const departmentId = doctorSnap.data().departmentId;

  const entriesRef = db
      .collection("queue_entries")
      .doc(hospitalId)
      .collection(date)
      .doc(departmentId)
      .collection("entries");

  // Backstop for the grace-period feature: if this doctor's currently
  // "called" patient has a graceDeadline that's already passed (client-side
  // countdown should normally have already auto-skipped them, but this
  // covers the case where nobody was looking — app closed, etc.), skip
  // them now before proceeding, so the doctor isn't permanently blocked.
  const activeSnap = await entriesRef
      .where("doctorId", "==", caller.uid)
      .where("status", "in", ["called", "in_consultation"])
      .limit(1)
      .get();

  if (!activeSnap.empty) {
    const activeDoc = activeSnap.docs[0];
    const activeData = activeDoc.data();
    const isOverdue =
      activeData.status === "called" &&
      activeData.graceDeadline &&
      activeData.graceDeadline.toMillis() < Date.now();

    if (isOverdue) {
      await activeDoc.ref.update({
        status: "skipped",
        doctorId: "",
        skippedAt: FieldValue.serverTimestamp(),
      });
      logger.info(`callNextPatient: auto-skipped overdue entry ${activeDoc.id} for doctor ${caller.uid} (backstop)`);
    } else {
      throw new HttpsError(
          "failed-precondition",
          "You already have an active patient. Complete or the current consultation before calling the next one.",
      );
    }
  }

  try {
    const result = await db.runTransaction(async (tx) => {
      const assignedSnap = await tx.get(
          entriesRef.where("doctorId", "==", caller.uid).where("status", "==", "waiting").limit(1),
      );

      let targetDoc;
      if (!assignedSnap.empty) {
        targetDoc = assignedSnap.docs[0];
      } else {
        const nextSnap = await tx.get(
            entriesRef
                .where("doctorId", "==", "")
                .where("status", "==", "waiting")
                .orderBy("priorityRank")
                .orderBy("checkedInAt")
                .limit(1),
        );
        if (nextSnap.empty) {
          return null;
        }
        targetDoc = nextSnap.docs[0];
      }

      const fresh = await tx.get(targetDoc.ref);
      if (!fresh.exists || fresh.data().status !== "waiting") {
        return null;
      }

      tx.update(targetDoc.ref, {
        doctorId: caller.uid,
        status: "called",
        calledAt: FieldValue.serverTimestamp(),
        warnedAt: null,
        graceDeadline: null,
      });

      const appointmentId = fresh.data().appointmentId;
      if (appointmentId) {
        tx.update(db.collection("appointments").doc(appointmentId), {doctorId: caller.uid});
      }

      return {entryId: targetDoc.id, ...fresh.data()};
    });

    if (!result) {
      throw new HttpsError("not-found", "No patients waiting.");
    }

    logger.info(`callNextPatient: doctor ${caller.uid} called entry ${result.entryId} (token #${result.tokenNumber})`);
    return {entryId: result.entryId, tokenNumber: result.tokenNumber, patientId: result.patientId};
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logger.error("callNextPatient: transaction failed", err);
    throw new HttpsError("internal", "Failed to call next patient.");
  }
});
