const functions = require("firebase-functions");
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

// ─── 1. Attendance trigger: punch-in / punch-out notifications ───────────────
exports.onAttendanceWrite = functions.firestore
  .document("Users/{userId}/Attendance/{date}")
  .onWrite(async (change, context) => {
    const { userId, date } = context.params;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    if (!after) return;

    // Get user info
    const userDoc = await db.collection("Users").doc(userId).get();
    if (!userDoc.exists) return;
    const user = userDoc.data();
    const userName = `${user.firstName} ${user.lastName}`;

    // Get direct manager only
    const manager = await getDirectManager(userId);
    if (!manager) return;
    const managerToken = manager.fcmToken;

    // Punch OUT detected (punchOutTimestamp newly set)
    const hadPunchOut = before && before.punchOutTimestamp;
    const hasPunchOut = after.punchOutTimestamp;

    if (!hadPunchOut && hasPunchOut) {
      const punchOutTime = after.punchOutTimestamp.toDate();
      const punchInTime = after.punchInTimestamp
        ? after.punchInTimestamp.toDate()
        : null;

      let durationText = "";
      if (punchInTime) {
        const diffMs = punchOutTime - punchInTime;
        const h = Math.floor(diffMs / 3600000);
        const m = Math.floor((diffMs % 3600000) / 60000);
        durationText = h > 0 ? `${h}h ${m}m` : `${m}m`;
      }

      await sendNotification(
        managerToken,
        `${userName} punched out`,
        durationText
          ? `Total time: ${durationText}`
          : "Has ended their work day.",
        {
          type: "punch_out",
          targetUserId: userId,
          targetUserName: userName,
        }
      );
    }
  });

// ─── 2. Visit trigger: check-in / check-out notifications ──────────────────
exports.onVisitWrite = functions.firestore
  .document("Users/{userId}/Visits/{visitId}")
  .onWrite(async (change, context) => {
    const { userId, visitId } = context.params;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

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
  });

// ─── 3. Comment trigger: notify user when manager comments ──────────────────
exports.onCommentWrite = functions.firestore
  .document("Users/{userId}/Visits/{visitId}/Comments/{commentId}")
  .onCreate(async (snap, context) => {
    const { userId, visitId, commentId } = context.params;
    const comment = snap.data();

    // Get visit owner
    const userDoc = await db.collection("Users").doc(userId).get();
    if (!userDoc.exists) return;
    const user = userDoc.data();
    const userToken = user.fcmToken;

    // Don't notify if the comment is by the user themselves
    if (comment.userId === userId) return;

    // Notify the visit owner
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

    // Also notify the commenter's manager if the user replied to a manager comment
    // (i.e., commenter is the visit owner replying back)
    // This case is handled by checking if the commenter is the visit owner
    if (comment.userId === userId) {
      const manager = await getDirectManager(userId);
      if (!manager || !manager.fcmToken) return;
      await sendNotification(
        manager.fcmToken,
        `${user.firstName} replied to your comment`,
        comment.text,
        {
          type: "comment_reply",
          targetUserId: userId,
          visitId,
          commentId,
        }
      );
    }
  });

// ─── 4. FCM token updater (called by client on login) ─────────────────────
exports.updateFcmToken = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    // Token updates happen when client writes fcmToken field
    // This is handled client-side; function is a no-op here
    // Token is stored in the User doc by the client
  });

// ─── 5. Reports hierarchy updater ────────────────────────────────────────────
// Triggered when a User document is created or updated
exports.updateReportsHierarchy = functions.firestore
  .document("Users/{userId}")
  .onWrite(async (change, context) => {
    const { userId } = context.params;

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    // Only act if managerId changed
    const prevManagerId = before ? before.managerId : null;
    const newManagerId = after ? after.managerId : null;

    if (prevManagerId === newManagerId) return;

    const userName =
      after ? `${after.firstName} ${after.lastName}` : "Unknown";

    // ── Remove from previous manager's reports tree ─────────────────────
    if (prevManagerId) {
      await removeFromManagerTree(prevManagerId, userId);
    }

    // ── Add to new manager's reports tree (and skip managers) ──────────
    if (newManagerId) {
      await addToManagerTree(newManagerId, userId, userName);
    }
  });

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

  // Also update skip managers above this manager
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
  let reports = mgrData.reports || {};

  // Get existing sub-reports of the user being added (if any)
  const userDoc = await db.collection("Users").doc(userId).get();
  const userReports = userDoc.exists ? (userDoc.data().reports || {}) : {};

  // Place userId directly under this manager
  function insertIntoDirectReports(node, targetManagerId) {
    if (targetManagerId === managerId) {
      node[userId] = { name: userName, reports: userReports };
      return true;
    }
    for (const key of Object.keys(node)) {
      if (key === targetManagerId) {
        node[key].reports = node[key].reports || {};
        node[key].reports[userId] = { name: userName, reports: userReports };
        return true;
      }
      if (node[key].reports && insertIntoDirectReports(node[key].reports, targetManagerId)) {
        return true;
      }
    }
    return false;
  }

  // For the immediate manager: add directly
  reports[userId] = { name: userName, reports: userReports };
  await db.collection("Users").doc(managerId).update({ reports });

  // For skip managers: add under their subtree
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

  // Find directManagerId in the tree and add userId under it
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

  // Continue up the chain
  const nextSkipId = skipData.managerId;
  if (nextSkipId) {
    await addToSkipManagerTree(nextSkipId, directManagerId, userId, userName, userReports);
  }
}
