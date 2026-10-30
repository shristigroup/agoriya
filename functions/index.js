const { onDocumentWritten, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const crypto = require("crypto");

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
        // lastBatchSyncedAt was called lastUpdatedAt in older builds.
        : ((data.lastBatchSyncedAt || data.lastUpdatedAt)
          ? (data.lastBatchSyncedAt || data.lastUpdatedAt).toMillis()
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
        const closedAt = new Date().toLocaleTimeString("en-IN", {
          hour: "numeric", minute: "2-digit", hour12: true, timeZone: "Asia/Kolkata",
        });
        await sendNotification(
          userToken,
          "Punched out automatically",
          `You were punched out at ${closedAt} because your phone stopped sending ` +
            "location. Open TrackFolks to resume your session.",
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

    // The claim is what Firestore rules trust, so it must belong to the caller:
    // the doc already registered to their phone number, or — for a new user —
    // an id that ends in their own phone number (ids are first-last-phone).
    const phone = decoded.phone_number;
    if (!phone) { res.status(403).json({ error: "Phone sign-in required" }); return; }
    const existing = await db.collection("Users").where("phoneNumber", "==", phone).limit(1).get();
    const allowed = existing.empty ? userId.endsWith(`-${phone}`) : existing.docs[0].id === userId;
    if (!allowed) { res.status(403).json({ error: "userId does not belong to caller" }); return; }

    await admin.auth().setCustomUserClaims(decoded.uid, { userId });
    res.status(200).json({ success: true });
  }
);

// ─── 8a. createOrgCode — the only place org codes are created ───────────────
// Called when a new user submits their profile without an org code. Clients
// cannot write Codes (firestore.rules), so the seat limit below is authoritative
// for new codes. Existing codes keep their own totalUserCount.
const FREE_USER_LIMIT = 10;
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no O/0/1/I ambiguity

exports.createOrgCode = onRequest(
  { region: "asia-south1", cors: true },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("Method Not Allowed"); return; }

    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!idToken) { res.status(401).json({ error: "Unauthenticated" }); return; }

    const decoded = await admin.auth().verifyIdToken(idToken);
    const userId = decoded.userId; // custom claim from setUserClaim
    if (!userId) { res.status(403).json({ error: "No userId claim" }); return; }

    // Reuse any code this user already owns.
    const existing = await db.collection("Codes").where("userId", "==", userId).limit(1).get();
    if (!existing.empty) { res.status(200).json({ code: existing.docs[0].id }); return; }

    for (let attempt = 0; attempt < 10; attempt++) {
      let code = "";
      for (let i = 0; i < 6; i++) code += CODE_CHARS[crypto.randomInt(CODE_CHARS.length)];
      try {
        await db.collection("Codes").doc(code).create({
          userId,
          totalUserCount: FREE_USER_LIMIT,
          currentUserCount: 1,
        });
        res.status(200).json({ code });
        return;
      } catch (err) {
        if (err.code !== 6) throw err; // 6 = ALREADY_EXISTS, try another code
      }
    }
    res.status(500).json({ error: "Could not generate unique org code" });
  }
);

// ─── 8b. deleteMyAccount — account & data deletion ──────────────────────────
// Two callers, one code path:
//   - a user deleting their OWN account (no targetUserId in the body), and
//   - a manager removing a member (targetUserId = the member), who must be
//     above the target in the manager chain.
// Both are refused while the target still has people reporting to them —
// those reports would otherwise be left pointing at a deleted manager.
//
// Wipes Users/{userId} and every nested subcollection (Tracking, Visits,
// Visits/{visitId}/Comments) in one call, then the target's Storage files
// (punch-in selfies, visit bills — both under a userId/ prefix, see
// AppConstants.punchInImagePath / billCopyPath), then their Auth credential.
// Firestore goes first so a partial failure never leaves a signed-in user
// whose data is gone but who can't retry: the only bad partial state is
// "data gone, auth still valid", which still lets them retry. syncOrgCodeCount
// and updateReportsHierarchy react to the doc delete on their own.
exports.deleteMyAccount = onRequest(
  { region: "asia-south1", cors: true },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("Method Not Allowed"); return; }

    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!idToken) { res.status(401).json({ error: "Unauthenticated" }); return; }

    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      res.status(401).json({ error: "Invalid token" });
      return;
    }
    const callerId = decoded.userId;
    if (!callerId) {
      res.status(400).json({ error: "No userId claim on this account" });
      return;
    }

    const requested = req.body && req.body.targetUserId;
    const targetId = (typeof requested === "string" && requested) ? requested : callerId;
    const isSelf = targetId === callerId;

    try {
      const targetSnap = await db.collection("Users").doc(targetId).get();
      if (!targetSnap.exists) { res.status(404).json({ error: "User not found" }); return; }
      const target = targetSnap.data();

      // Authorize: a manager may only act on someone below them in the chain.
      // Walk managerId upward rather than trusting the maintained `managers`
      // array, which can be stale.
      if (!isSelf) {
        let cursor = target.managerId || null;
        const seen = new Set();
        let isAbove = false;
        while (cursor && !seen.has(cursor)) {
          if (cursor === callerId) { isAbove = true; break; }
          seen.add(cursor);
          const m = await db.collection("Users").doc(cursor).get();
          cursor = m.exists ? (m.data().managerId || null) : null;
        }
        if (!isAbove) { res.status(403).json({ error: "forbidden" }); return; }
      }

      // Refuse if anyone still reports to the target. Query the real
      // managerId links, not the derived `reports` map.
      const reportSnap = await db.collection("Users")
        .where("managerId", "==", targetId).limit(1).get();
      if (!reportSnap.empty) {
        res.status(409).json({ error: "has_reports" });
        return;
      }

      // Resolve the target's Auth uid before their doc is gone.
      let targetAuthUid = isSelf ? decoded.uid : (target.uid || null);
      if (!targetAuthUid && target.phoneNumber) {
        try {
          targetAuthUid = (await admin.auth().getUserByPhoneNumber(target.phoneNumber)).uid;
        } catch (_) { /* no auth record; nothing to delete */ }
      }

      console.log(`[deleteMyAccount] ${callerId} deleting ${targetId}${isSelf ? " (self)" : ""}`);

      await db.recursiveDelete(db.collection("Users").doc(targetId));

      // Best-effort — Firestore data and the auth account are what matter
      // most, and are already handled by this point.
      try {
        await admin.storage().bucket().deleteFiles({ prefix: `${targetId}/` });
      } catch (err) {
        console.error(`[deleteMyAccount] storage cleanup failed for ${targetId}:`, err.message);
      }

      // Update the manager's tree now so the caller's list is correct as soon
      // as this returns (updateReportsHierarchy would do it a moment later).
      if (target.managerId) {
        try { await removeFromManagerTree(target.managerId, targetId); }
        catch (err) { console.error("[deleteMyAccount] tree cleanup failed:", err.message); }
      }

      if (targetAuthUid) {
        try {
          await admin.auth().deleteUser(targetAuthUid);
        } catch (err) {
          if (err.code !== "auth/user-not-found") throw err;
        }
      }

      console.log(`[deleteMyAccount] completed for ${targetId}`);
      res.status(200).json({ success: true });
    } catch (err) {
      console.error("[deleteMyAccount] failed:", err);
      res.status(500).json({ error: "internal" });
    }
  }
);

// ─── 9. exportMonthlyReport — server-side CSV export ─────────────────────────
// Builds the day-wise attendance CSV for everyone below the caller in the
// reporting tree and returns it in the response, plus a private copy under
// exports/{userId}/ (no Storage rule matches that path, so clients cannot read
// it; a bucket lifecycle rule on the exports/ prefix should expire it). Reads
// run here, with field selection, instead of on the phone, and every run is
// logged so missing rows can be diagnosed.
//
// Request:  POST { monthKey: "yyyy-MM", tzOffsetMinutes?: number }
// Response: 200 { csv, filename, rowCount, memberCount, failedMembers, skippedDocs }
function csvEscape(v) {
  const s = String(v == null ? "" : v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
function pad2(n) { return String(n).padStart(2, "0"); }
function fmtHHmm(ms, offsetMin) {
  const d = new Date(ms + offsetMin * 60000);
  return `${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}`;
}
function fmtDuration(ms) {
  const h = Math.floor(ms / 3600000);
  const m = Math.floor(ms / 60000) % 60;
  if (h === 0) return `${m}m`;
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}
function flattenReports(node, out = []) {
  for (const [id, v] of Object.entries(node || {})) {
    out.push({ id, name: (v && v.name) || "" });
    if (v && v.reports) flattenReports(v.reports, out);
  }
  return out;
}
async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      results[i] = await fn(items[i]);
    }
  });
  await Promise.all(workers);
  return results;
}

exports.exportMonthlyReport = onRequest(
  { region: "asia-south1", cors: true, timeoutSeconds: 60, memory: "512MiB" },
  async (req, res) => {
    const startedAt = Date.now();
    if (req.method !== "POST") { res.status(405).send("Method Not Allowed"); return; }

    const authHeader = req.headers.authorization || "";
    const idToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!idToken) { res.status(401).json({ error: "Unauthenticated" }); return; }
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (err) {
      res.status(401).json({ error: "Invalid token" });
      return;
    }
    const callerId = decoded.userId;
    if (!callerId) { res.status(400).json({ error: "No userId claim on this account" }); return; }

    const body = req.body || {};
    const monthKey = String(body.monthKey || "");
    if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(monthKey)) {
      res.status(400).json({ error: "invalid_month" });
      return;
    }
    // Month boundaries in the caller's local time (device offset); IST default.
    let offsetMin = Number(body.tzOffsetMinutes);
    if (!Number.isFinite(offsetMin) || Math.abs(offsetMin) > 14 * 60) offsetMin = 330;
    const [year, month] = monthKey.split("-").map(Number);
    const startMs = Date.UTC(year, month - 1, 1) - offsetMin * 60000;
    const endMs = Date.UTC(year, month, 1) - offsetMin * 60000;

    try {
      const callerSnap = await db.collection("Users").doc(callerId).get();
      if (!callerSnap.exists) { res.status(404).json({ error: "User not found" }); return; }

      const byId = new Map();
      flattenReports(callerSnap.data().reports).forEach((m) => byId.set(m.id, m));
      const members = [...byId.values()];

      const fetched = await mapLimit(members, 20, async (mem) => {
        try {
          const snap = await db.collection("Users").doc(mem.id).collection("Tracking")
            .where("startTime", ">=", admin.firestore.Timestamp.fromMillis(startMs))
            .where("startTime", "<", admin.firestore.Timestamp.fromMillis(endMs))
            .select("startTime", "stopTime", "distance")
            .get();
          const sessions = [];
          const skipped = [];
          snap.docs.forEach((d) => {
            try {
              const x = d.data();
              sessions.push({
                date: d.id.substring(0, 10),
                startMs: x.startTime.toMillis(),
                stopMs: x.stopTime ? x.stopTime.toMillis() : null,
                distance: Number(x.distance) || 0,
              });
            } catch (e) {
              skipped.push({ id: d.id, error: String(e.message || e).slice(0, 120) });
            }
          });
          return { mem, sessions, skipped, error: null };
        } catch (err) {
          console.error(`[exportMonthlyReport] fetch failed for ${mem.id}:`, err.message);
          return { mem, sessions: [], skipped: [], error: String(err.message || err).slice(0, 200) };
        }
      });

      const rows = [];
      fetched.forEach((f) => f.sessions.forEach((s) => rows.push({ name: f.mem.name, ...s })));
      rows.sort((a, b) => a.name.localeCompare(b.name) || a.date.localeCompare(b.date));

      const lines = ["Name,Date,Punch In,Punch Out,Total Hours,Distance (km)"];
      rows.forEach((r) => {
        lines.push([
          csvEscape(r.name),
          r.date,
          fmtHHmm(r.startMs, offsetMin),
          r.stopMs != null ? fmtHHmm(r.stopMs, offsetMin) : "",
          r.stopMs != null ? fmtDuration(r.stopMs - r.startMs) : "",
          r.distance.toFixed(1),
        ].join(","));
      });
      const csv = lines.join("\n") + "\n";

      const failedMembers = fetched.filter((f) => f.error).length;
      const skippedDocs = fetched.reduce((n, f) => n + f.skipped.length, 0);
      const filename = `trackfolks_${monthKey}.csv`;

      // Private, short-lived copy for support/audit. Best-effort.
      try {
        await admin.storage().bucket()
          .file(`exports/${callerId}/${filename.replace(".csv", "")}_${Date.now()}.csv`)
          .save(csv, { contentType: "text/csv", resumable: false });
      } catch (err) {
        console.error(`[exportMonthlyReport] storage copy failed for ${callerId}:`, err.message);
      }

      // One structured entry per run: who, what range, and per member the
      // session count and the exact dates that came back.
      console.log(JSON.stringify({
        event: "export_monthly_report",
        callerId, monthKey, tzOffsetMinutes: offsetMin,
        rangeStartUtc: new Date(startMs).toISOString(),
        rangeEndUtc: new Date(endMs).toISOString(),
        members: members.length, sessions: rows.length,
        failedMembers, skippedDocs,
        durationMs: Date.now() - startedAt,
        perMember: fetched.map((f) => ({
          id: f.mem.id,
          n: f.sessions.length,
          dates: [...new Set(f.sessions.map((s) => s.date))].sort(),
          ...(f.error ? { error: f.error } : {}),
          ...(f.skipped.length ? { skipped: f.skipped } : {}),
        })),
      }));

      res.status(200).json({
        csv, filename, rowCount: rows.length,
        memberCount: members.length, failedMembers, skippedDocs,
      });
    } catch (err) {
      console.error(`[exportMonthlyReport] failed for ${callerId} ${monthKey}:`, err);
      res.status(500).json({ error: "internal" });
    }
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

// ─── Stripe payments (see stripe.js) ────────────────────────────────────────
const stripePayments = require("./stripe");
exports.createCheckoutSession = stripePayments.createCheckoutSession;
exports.stripeWebhook = stripePayments.stripeWebhook;
