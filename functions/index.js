const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// ─── Helper: get FCM token for a user ────────────────────────────────────────
async function getUserToken(userId) {
  const doc = await db.collection("Users").doc(userId).get();
  return doc.exists ? doc.data().fcmToken : null;
}

// ─── Helper: send FCM notification ──────────────────────────────────────────
async function sendNotification(token, title, body, data = {}) {
  if (!token) return;
  try {
    await messaging.send({
      token,
      notification: { title, body },
      data: { ...data },
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    });
  } catch (err) {
    console.error("FCM send error:", err.message);
  }
}

// ─── Helper: get direct manager of a user ────────────────────────────────────
async function getDirectManager(userId) {
  const userDoc = await db.collection("Users").doc(userId).get();
  if (!userDoc.exists) return null;
  const managerId = userDoc.data().managerId;
  if (!managerId) return null;
  const mgrDoc = await db.collection("Users").doc(managerId).get();
  return mgrDoc.exists ? { id: managerId, ...mgrDoc.data() } : null;
}

// ─── Helper: format duration ms → "Xh Ym" ────────────────────────────────────
function formatDuration(ms) {
  const h = Math.floor(ms / 3600000);
  const m = Math.floor((ms % 3600000) / 60000);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

// ─── 1. Tracking trigger: punch-in / punch-out / resume notifications ─────────
exports.onTrackingWrite = onDocumentWritten(
  { document: "Users/{userId}/Tracking/{trackingId}", region: "asia-south1" },
  async (event) => {
    const { userId } = event.params;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    if (!after) return;

    const userDoc = await db.collection("Users").doc(userId).get();
    if (!userDoc.exists) return;
    const user = userDoc.data();
    const userName = `${user.firstName} ${user.lastName}`;

    const manager = await getDirectManager(userId);
    if (!manager) return;
    const managerToken = manager.fcmToken;

    const hadStopTime = before && before.stopTime;
    const hasStopTime = after.stopTime;

    // ── New doc created = punch-in ─────────────────────────────────────────
    if (!before) {
      await sendNotification(
        managerToken,
        `${userName} punched in`,
        "Started work",
        {
          type: "punch_in",
          targetUserId: userId,
          targetUserName: userName,
        }
      );
      return;
    }

    // ── stopTime removed = resume session ─────────────────────────────────
    if (hadStopTime && !hasStopTime) {
      await sendNotification(
        managerToken,
        `${userName} resumed session`,
        "Session resumed",
        {
          type: "resume",
          targetUserId: userId,
          targetUserName: userName,
        }
      );
      return;
    }

    // ── stopTime newly set = punch-out ────────────────────────────────────
    if (!hadStopTime && hasStopTime) {
      const punchInTime = after.startTime ? after.startTime.toDate() : null;
      const durationText = punchInTime
        ? formatDuration(after.stopTime.toDate() - punchInTime) : "";

      await sendNotification(
        managerToken,
        `${userName} punched out`,
        durationText ? `Total time: ${durationText}` : "Has ended their work day.",
        {
          type: "punch_out",
          targetUserId: userId,
          targetUserName: userName,
        }
      );
      return;
    }

    // ── last location's durationSeconds crossed 30 min threshold ─────────
    const prevLocations = (before && before.locations) || [];
    const curLocations = after.locations || [];
    const prevDuration = prevLocations.length > 0
        ? (prevLocations[prevLocations.length - 1].durationSeconds || 0) : 0;
    const curDuration = curLocations.length > 0
        ? (curLocations[curLocations.length - 1].durationSeconds || 0) : 0;
    const threshold = 1800; // 30 minutes
    if (prevDuration < threshold && curDuration >= threshold) {
      await sendNotification(
        managerToken,
        `${userName} is stationary`,
        "Has been at the same location for 30 minutes.",
        { type: "stationary", targetUserId: userId, targetUserName: userName }
      );
    }
  }
);

// ─── 2. Visit trigger: check-in / check-out notifications ──────────────────
exports.onVisitWrite = onDocumentWritten(
  { document: "Users/{userId}/Visits/{visitId}", region: "asia-south1" },
  async (event) => {
    const { userId, visitId } = event.params;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    if (!after) return;

    const userDoc = await db.collection("Users").doc(userId).get();
    if (!userDoc.exists) return;
    const user = userDoc.data();
    const userName = `${user.firstName} ${user.lastName}`;

    const manager = await getDirectManager(userId);
    if (!manager) return;
    const managerToken = manager.fcmToken;

    const clientName = after.clientName || "a client";

    // New visit created = check-in
    if (!before) {
      await sendNotification(
        managerToken,
        `${userName} checked in`,
        `At ${clientName} — ${after.location || ""}`,
        {
          type: "check_in",
          targetUserId: userId,
          targetUserName: userName,
          visitId,
        }
      );
      return;
    }

    // Checkout newly added
    const hadCheckout = before.checkoutTimestamp;
    const hasCheckout = after.checkoutTimestamp;
    if (!hadCheckout && hasCheckout) {
      await sendNotification(
        managerToken,
        `${userName} checked out`,
        `From ${clientName}`,
        {
          type: "check_out",
          targetUserId: userId,
          targetUserName: userName,
          visitId,
        }
      );
    }
  }
);

// ─── 3. Comment trigger: notify user when manager comments ──────────────────
exports.onCommentWrite = onDocumentCreated(
  { document: "Users/{userId}/Visits/{visitId}/Comments/{commentId}", region: "asia-south1" },
  async (event) => {
    const { userId, visitId, commentId } = event.params;
    const comment = event.data.data();

    const userDoc = await db.collection("Users").doc(userId).get();
    if (!userDoc.exists) return;
    const user = userDoc.data();
    const userToken = user.fcmToken;

    // Don't notify if the comment is by the user themselves
    if (comment.userId === userId) return;

    await sendNotification(
      userToken,
      `${comment.userName} commented on your visit`,
      comment.text,
      {
        type: "comment",
        targetUserId: userId,
        visitId,
        commentId,
      }
    );
  }
);

// ─── 4. FCM token updater (no-op — token is written client-side) ─────────────
// exports.updateFcmToken = onDocumentWritten(
//   { document: "Users/{userId}", region: "asia-south1" },
//   async (event) => {
//     // Token updates are handled client-side; this function is intentionally empty.
//   }
// );

// ─── 5. Reports hierarchy updater ────────────────────────────────────────────
exports.updateReportsHierarchy = onDocumentWritten(
  { document: "Users/{userId}", region: "asia-south1" },
  async (event) => {
    const { userId } = event.params;

    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    const prevManagerId = before ? before.managerId : null;
    const newManagerId = after ? after.managerId : null;

    if (prevManagerId === newManagerId) return;

    if (prevManagerId) {
      await removeFromManagerTree(prevManagerId, userId);
    }

    if (newManagerId) {
      const userName = after ? `${after.firstName} ${after.lastName}` : "Unknown";
      await addToManagerTree(newManagerId, userId, userName);
    }
  }
);


// Remove userId from a manager's reports JSON recursively (including skip levels)
async function removeFromManagerTree(managerId, userId) {
  const mgrDoc = await db.collection("Users").doc(managerId).get();
  if (!mgrDoc.exists) return;

  const mgrData = mgrDoc.data();
  const reports = mgrData.reports || {};

  function removeFromNode(node) {
    if (node[userId]) {
      delete node[userId];
      return true;
    }
    for (const key of Object.keys(node)) {
      if (node[key].reports && removeFromNode(node[key].reports)) {
        return true;
      }
    }
    return false;
  }

  removeFromNode(reports);
  await db.collection("Users").doc(managerId).update({ reports });

  const mgrManagerId = mgrData.managerId;
  if (mgrManagerId) {
    await removeFromManagerTree(mgrManagerId, userId);
  }
}

// Add userId to manager's reports JSON, and recursively to skip managers
async function addToManagerTree(managerId, userId, userName) {
  const mgrDoc = await db.collection("Users").doc(managerId).get();
  if (!mgrDoc.exists) return;

  const mgrData = mgrDoc.data();
  const reports = mgrData.reports || {};

  const userDoc = await db.collection("Users").doc(userId).get();
  const userReports = userDoc.exists ? (userDoc.data().reports || {}) : {};

  reports[userId] = { name: userName, reports: userReports };
  await db.collection("Users").doc(managerId).update({ reports });

  const skipManagerId = mgrData.managerId;
  if (skipManagerId) {
    await addToSkipManagerTree(skipManagerId, managerId, userId, userName, userReports);
  }
}

// Recursively add to skip managers preserving hierarchy position
async function addToSkipManagerTree(skipManagerId, directManagerId, userId, userName, userReports) {
  const skipDoc = await db.collection("Users").doc(skipManagerId).get();
  if (!skipDoc.exists) return;

  const skipData = skipDoc.data();
  const reports = skipData.reports || {};

  function insertUnder(node, parentId) {
    if (node[parentId]) {
      node[parentId].reports = node[parentId].reports || {};
      node[parentId].reports[userId] = { name: userName, reports: userReports };
      return true;
    }
    for (const key of Object.keys(node)) {
      if (node[key].reports && insertUnder(node[key].reports, parentId)) {
        return true;
      }
    }
    return false;
  }

  insertUnder(reports, directManagerId);
  await db.collection("Users").doc(skipManagerId).update({ reports });

  const nextSkipId = skipData.managerId;
  if (nextSkipId) {
    await addToSkipManagerTree(nextSkipId, directManagerId, userId, userName, userReports);
  }
}
