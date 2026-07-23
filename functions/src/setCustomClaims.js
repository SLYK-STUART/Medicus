const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {getAuth} = require("firebase-admin/auth");
const logger = require("firebase-functions/logger");

const VALID_ROLES = ["super_admin", "hospital_admin", "receptionist", "doctor", "patient"];

exports.onUserDocWritten = onDocumentWritten("users/{userId}", async (event) => {
  const userId = event.params.userId;
  const data = event.data?.after?.data();

  if (!data) {
    // Doc was deleted — nothing to sync.
    return;
  }

  const {role, hospitalId} = data;

  if (!VALID_ROLES.includes(role)) {
    logger.error(`onUserDocWritten: invalid role "${role}" on users/${userId}, skipping`);
    return;
  }

  await getAuth().setCustomUserClaims(userId, {
    role,
    hospitalId: hospitalId ?? null,
  });

  logger.info(`Synced claims for ${userId}: role=${role}, hospitalId=${hospitalId ?? null}`);
});
