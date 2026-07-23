const {initializeApp} = require("firebase-admin/app");
const {setGlobalOptions} = require("firebase-functions/v2");
const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

initializeApp();
setGlobalOptions({maxInstances: 10});

exports.helloWorld = onRequest((request, response) => {
  logger.info("Hello logs!", {structuredData: true});
  response.send("Hello from Firebase!");
});

exports.onUserDocWritten = require("./src/setCustomClaims").onUserDocWritten;
exports.createStaffAccount = require("./src/createStaffAccount").createStaffAccount;
exports.createAppointment = require("./src/createAppointment").createAppointment;
exports.createWalkInPatient = require("./src/createWalkInPatient").createWalkInPatient;
exports.callNextPatient = require("./src/callNextPatient").callNextPatient;
exports.onQueueEntryWritten = require("./src/queueNotifications").onQueueEntryWritten;
exports.onConsultationCompleted = require("./src/consultationAverages").onConsultationCompleted;
exports.createReferral = require("./src/createReferral").createReferral;
exports.createFollowUpAppointment = require("./src/createFollowUpAppointment").createFollowUpAppointment;
exports.getAvailableSlots = require("./src/getAvailableSlots").getAvailableSlots;
exports.warnPatientDelay = require("./src/warnPatientDelay").warnPatientDelay;
exports.rescheduleAppointment = require("./src/rescheduleAppointment").rescheduleAppointment;
