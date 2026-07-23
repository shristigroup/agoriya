const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// ─── Location tracking tuning (see functions/.env.example) ──────────────────
// Loaded automatically from functions/.env on deploy/emulate (functions v2).
const LOCATION_SAMPLE_INTERVAL_MINUTE = Number(process.env.LOCATION_SAMPLE_INTERVAL_MINUTE || 1);
const WATCHDOG_SCHEDULE_MINUTES = Number(process.env.WATCHDOG_SCHEDULE_MINUTES || 5);
const WATCHDOG_PING_COUNT_THRESHOLD = Number(process.env.WATCHDOG_PING_COUNT_THRESHOLD || 2);

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

// ─── Location tracking watchdog — recover tracking the OS killed ────────────
// Runs every WATCHDOG_SCHEDULE_MINUTES. Finds punched-in users whose
// locationHeartbeatTimestamp (written by the app on every GPS sample — much
// more frequent than the actual Firestore location-batch sync) has gone
// stale, and sends a silent, data-only FCM message that the app uses to
// restart tracking in the background — without waiting for the user to
// reopen the app. Reliable on Android unless the user has force-stopped the
// app; on iOS this is a best-effort improvement since Apple can throttle
// silent push delivery.
//
// If a doc keeps failing to recover after WATCHDOG_PING_COUNT_THRESHOLD
// pings (e.g. FCM delivery itself is blocked — force-stopped app, or a
// platform limitation), the watchdog gives up: auto punches the user out,
// notifies them directly (so they can reopen the app and punch back in,
// which restarts every service cleanly), and the existing onTrackingWrite
// trigger above notifies the manager automatically since it reacts to the
// stopTime write itself, regardless of who/what made it.
const HEARTBEAT_STALE_THRESHOLD_MS = 2 * LOCATION_SAMPLE_INTERVAL_MINUTE * 60 * 1000;

exports.locationTrackingWatchdog = onSchedule(
  { schedule: `every ${WATCHDOG_SCHEDULE_MINUTES} minutes`, region: "asia-south1" },
  async () => {
    const now = Date.now();
    const snap = await db
      .collectionGroup("Tracking")
      .where("isPunchedIn", "==", true)
      .get();

    await Promise.all(snap.docs.map(async (doc) => {
      const data = doc.data();
      const heartbeatAt = data.locationHeartbeatTimestamp
        ? data.locationHeartbeatTimestamp.toMillis()
        : (data.lastUpdatedAt
          ? data.lastUpdatedAt.toMillis()
          : (data.startTime ? data.startTime.toMillis() : now));

      const userId = doc.ref.parent.parent.id;
      const date = doc.id.substring(0, 10);
      const trackingId = doc.id;

      if (now - heartbeatAt < HEARTBEAT_STALE_THRESHOLD_MS) return;

      const pingedAtMs = data.watchdogPingedAt ? data.watchdogPingedAt.toMillis() : null;

      // Recovered since the last ping — fresh heartbeat arrived, clear
      // episode state so the next unrelated stale spell starts clean.
      if (pingedAtMs !== null && heartbeatAt >= pingedAtMs) {
        await doc.ref.update({
          watchdogPingedAt: admin.firestore.FieldValue.delete(),
          watchdogPingCount: admin.firestore.FieldValue.delete(),
        });
        return;
      }

      // Increment before deciding, so a pingCount that's already at
      // threshold is acted on THIS run — not one extra WATCHDOG_SCHEDULE_
      // MINUTES cycle later, which sending-then-checking-next-time would
      // otherwise waste. This means the ping numbered at the threshold is
      // never actually sent — give-up takes its place once the last
      // ACTUAL ping (pingCount - 1 sends) has had one full cycle to prove
      // it worked.
      const nextPingCount = (data.watchdogPingCount || 0) + 1;

      if (pingedAtMs !== null && nextPingCount >= WATCHDOG_PING_COUNT_THRESHOLD) {
        await doc.ref.update({
          stopTime: admin.firestore.Timestamp.now(),
          isPunchedIn: false,
          watchdogPingedAt: admin.firestore.FieldValue.delete(),
          watchdogPingCount: admin.firestore.FieldValue.delete(),
          autoClosedReason: "no_location_data",
        });
        // Manager notification fires automatically via onTrackingWrite's
        // stopTime branch above — this only needs to tell the worker.
        const userToken = await getUserToken(userId);
        await sendNotification(
          userToken,
          "Punched out automatically",
          "You were punched out because your location data stopped syncing.",
          { type: "auto_punch_out", trackingId }
        );
        console.log(`[locationTrackingWatchdog] auto punch-out → ${userId} (${doc.id})`);
        return;
      }

      // Never pinged yet, or still under threshold — (re)ping.
      const token = await getUserToken(userId);
      if (!token) return;

      try {
        await messaging.send({
          token,
          data: { type: "location_wakeup", userId, date, trackingId },
          android: { priority: "high" },
          apns: {
            headers: { "apns-priority": "5" },
            payload: { aps: { "content-available": 1 } },
          },
        });
        await doc.ref.update({
          watchdogPingedAt: admin.firestore.FieldValue.serverTimestamp(),
          watchdogPingCount: nextPingCount,
        });
        console.log(`[locationTrackingWatchdog] wakeup sent → ${userId} (${doc.id}), attempt ${nextPingCount}`);
      } catch (err) {
        console.error(`[locationTrackingWatchdog] send error for ${userId}:`, err.message);
      }
    }));
  }
);

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

// ─── 6. Org code seat count — stateless resync on any User write ─────────────
// Fires whenever a User doc changes. If the code field changed, counts all
// users sharing each affected code and writes currentUserCount directly.
// No increment/decrement needed — the count is always derived from source.
exports.syncOrgCodeCount = onDocumentWritten(
  { document: "Users/{userId}", region: "asia-south1" },
  async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    const prevCode = before ? (before.code || null) : null;
    const newCode = after ? (after.code || null) : null;

    if (prevCode === newCode) return;

    const codesToSync = new Set();
    if (prevCode) codesToSync.add(prevCode);
    if (newCode) codesToSync.add(newCode);

    await Promise.all([...codesToSync].map(async (code) => {
      const codeDoc = await db.collection("Codes").doc(code).get();
      if (!codeDoc.exists) return;
      const snap = await db.collection("Users").where("code", "==", code).get();
      await db.collection("Codes").doc(code).update({ currentUserCount: snap.size });
      console.log(`[syncOrgCodeCount] ${code} → ${snap.size} members`);
    }));
  }
);

// ─── 7. Managers array: keep CF-maintained list of manager UIDs on each user ──
// This array is used by Firestore rules to grant managers read/write access
// to their reports' documents without a separate query.
exports.updateManagersArray = onDocumentWritten(
  { document: "Users/{userId}", region: "asia-south1" },
  async (event) => {
    const { userId } = event.params;
    const before = event.data.before.exists ? event.data.before.data() : null;
    const after = event.data.after.exists ? event.data.after.data() : null;

    if (!after) return;

    const prevManagerId = before ? before.managerId : null;
    const newManagerId = after.managerId || null;

    // Only run when managerId actually changes
    if (prevManagerId === newManagerId) return;

    // Walk the manager chain upward, collecting User doc IDs
    const managerIds = [];
    let currentManagerDocId = newManagerId;
    const visited = new Set();

    while (currentManagerDocId && !visited.has(currentManagerDocId)) {
      visited.add(currentManagerDocId);
      const mgrDoc = await db.collection("Users").doc(currentManagerDocId).get();
      if (!mgrDoc.exists) break;
      managerIds.push(currentManagerDocId);
      currentManagerDocId = mgrDoc.data().managerId || null;
    }

    await db.collection("Users").doc(userId).update({ managers: managerIds });
    console.log(`[updateManagersArray] ${userId} managers set to`, managerIds);
  }
);

// ─── 8. setUserClaim — sets userId custom claim on the caller's auth token ────
// Called post-submit during login, before any Firestore writes, so that
// request.auth.token.userId is available in security rules.
const { onRequest } = require("firebase-functions/v2/https");

exports.setUserClaim = onRequest(
  { region: "asia-south1", cors: true },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("Method Not Allowed"); return; }

    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!idToken) { res.status(401).json({ error: "Unauthenticated" }); return; }

    const { userId } = req.body;
    if (!userId || typeof userId !== "string") {
      res.status(400).json({ error: "Invalid userId" });
      return;
    }

    const decoded = await admin.auth().verifyIdToken(idToken);
    await admin.auth().setCustomUserClaims(decoded.uid, { userId });
    res.status(200).json({ success: true });
  }
);

// ─── 8. getUserByPhone — authenticated HTTP endpoint ─────────────────────────
// Used during login to look up a user doc by phone number server-side,
// bypassing Firestore client rules cleanly via Admin SDK.
exports.getUserByPhone = onRequest(
  { region: "asia-south1", cors: true },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("Method Not Allowed"); return; }

    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!idToken) { res.status(401).json({ error: "Unauthenticated" }); return; }

    await admin.auth().verifyIdToken(idToken);

    const { phoneNumber } = req.body;
    if (!phoneNumber) { res.status(400).json({ error: "phoneNumber required" }); return; }

    const snap = await db.collection("Users")
      .where("phoneNumber", "==", phoneNumber)
      .limit(1)
      .get();

    if (snap.empty) { res.status(200).json({ user: null }); return; }

    const doc = snap.docs[0];
    res.status(200).json({ user: { id: doc.id, ...doc.data() } });
  }
);

// ─── 9. getOrgMembers — unauthenticated HTTP endpoint ────────────────────────
// Called from the login screen before the user is authenticated.
// Returns all users sharing the given org code (id + name only).

exports.getOrgMembers = onRequest(
  { region: "asia-south1", cors: true },
  async (req, res) => {
    const code = (req.query.code || "").trim().toUpperCase();
    if (!code || code.length !== 6) {
      res.status(400).json({ error: "Invalid code" });
      return;
    }

    const codeDoc = await db.collection("Codes").doc(code).get();
    if (!codeDoc.exists) {
      res.status(404).json({ error: "Code not found" });
      return;
    }

    const snap = await db.collection("Users")
      .where("code", "==", code)
      .get();

    const members = snap.docs.map((d) => {
      const data = d.data();
      return {
        id: d.id,
        uid: data.uid || "",
        firstName: data.firstName || "",
        lastName: data.lastName || "",
      };
    });

    res.status(200).json({ members });
  }
);
