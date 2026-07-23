const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {getFirestore} = require("firebase-admin/firestore");

function parseTime(t) {
  const [h, m] = t.split(":").map(Number);
  return h * 60 + m;
}
function formatTime(minutes) {
  const h = String(Math.floor(minutes / 60)).padStart(2, "0");
  const m = String(minutes % 60).padStart(2, "0");
  return `${h}:${m}`;
}
function generateSlots(openTime, closeTime, slotDurationMinutes) {
  const slots = [];
  let current = parseTime(openTime);
  const close = parseTime(closeTime);
  while (current + slotDurationMinutes <= close) {
    slots.push(`${formatTime(current)}-${formatTime(current + slotDurationMinutes)}`);
    current += slotDurationMinutes;
  }
  return slots;
}

exports.getAvailableSlots = onCall(async (request) => {
  const caller = request.auth;
  if (!caller) throw new HttpsError("unauthenticated", "Must be signed in.");

  const {hospitalId, departmentId, date} = request.data ?? {};
  if (!hospitalId || !departmentId || !date) {
    throw new HttpsError("invalid-argument", "hospitalId, departmentId, and date are required.");
  }

  const db = getFirestore();

  const deptSnap = await db.collection("departments").doc(departmentId).get();
  if (!deptSnap.exists) throw new HttpsError("not-found", "Department not found.");
  const dept = deptSnap.data();

  // Server-side, Admin SDK — bypasses rules entirely, which is exactly
  // what's needed here: counting OTHER patients' bookings, something no
  // patient's own client read is allowed to do directly.
  const apptsSnap = await db
      .collection("appointments")
      .where("hospitalId", "==", hospitalId)
      .where("departmentId", "==", departmentId)
      .where("scheduledDate", "==", date)
      .where("status", "in", ["booked", "checked_in"])
      .get();

  const countsBySlot = {};
  apptsSnap.forEach((doc) => {
    const slot = doc.data().scheduledTimeSlot;
    if (slot) countsBySlot[slot] = (countsBySlot[slot] ?? 0) + 1;
  });

  const capacity = dept.slotCapacity ?? 5;
  const slots = generateSlots(dept.openTime ?? "08:00", dept.closeTime ?? "17:00", dept.slotDurationMinutes ?? 30).map(
      (slot) => ({slot, remaining: capacity - (countsBySlot[slot] ?? 0)}),
  );

  return {slots};
});
