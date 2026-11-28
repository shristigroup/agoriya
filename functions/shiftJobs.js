// The work behind shift reminders, with everything outside the project passed
// in (the task queue, the push sender, Firestore reads), so it can be tested
// with fakes and against the Firestore emulator (test/shiftJobs.test.js).
const admin = require("firebase-admin");
const shifts = require("./shifts");

// Queue the reminders still ahead for the shift day that starts on dateStr.
// `enqueue(payload, { scheduleTime, id })` is the Cloud Tasks call.
async function queueShiftTasks({ enqueue, code, shiftId, shift, dateStr, now, log = console }) {
  let queued = 0;
  for (const t of shifts.dueTasks(shift, dateStr, now)) {
    try {
      await enqueue(
        { code, shiftId, kind: t.kind, date: dateStr, expectedAt: t.expectedAt },
        {
          scheduleTime: t.scheduleTime,
          // Unique per shift, day, kind and time: an edit makes a new task, and
          // the midnight job can run twice without queueing a duplicate.
          id: `${shiftId}-${dateStr}-${t.kind}-${t.expectedAt}`,
        }
      );
      queued++;
    } catch (err) {
      if (!/already exists|task-already-exists/i.test(`${err.code} ${err.message}`)) {
        log.error(`[shifts] could not queue ${t.kind} for ${code}/${shiftId}:`, err.message);
      }
    }
  }
  return queued;
}

// Firestore reads used by the reminder. `db` is an admin Firestore.
function makeShiftData(db) {
  return {
    async getShift(code, shiftId) {
      const d = await db.doc(`Codes/${code}/Shifts/${shiftId}`).get();
      return d.exists ? d.data() : null;
    },
    // Sessions from `since` (a yyyy-MM-dd; session ids start with their date) on.
    async getSessions(userId, since) {
      const snap = await db.collection("Users").doc(userId).collection("Tracking")
        .orderBy(admin.firestore.FieldPath.documentId()).startAt(since)
        .select("isPunchedIn").get();
      return snap.docs.map((d) => ({ id: d.id, isPunchedIn: d.get("isPunchedIn") === true }));
    },
    async getToken(userId) {
      const u = await db.collection("Users").doc(userId).get();
      return (u.exists && u.data().fcmToken) || null;
    },
  };
}

// The Cloud Task for one reminder: notify the shift's people who need it.
// Returns how many were notified.
async function runShiftReminder({ data, getShift, getSessions, getToken, send, log = console }) {
  const { code, shiftId, kind, date, expectedAt } = data;
  const shift = await getShift(code, shiftId);
  if (!shift) return 0;
  if (shifts.isStale(shift, date, kind, expectedAt)) return 0;

  const title = kind === "in" ? "Time to punch in" : "Time to punch out";
  const body = shift.name ? `${shift.name} shift` : "Your shift";
  const since = shifts.addDays(date, -1);

  const remind = async (userId) => {
    // Someone with a session today, or one still open from last night, is not
    // nudged to punch in; only someone with an open session is nudged to punch out.
    const sessions = await getSessions(userId, since);
    const open = sessions.some((s) => s.isPunchedIn);
    const today = sessions.some((s) => s.id.startsWith(date));
    if (kind === "in" ? (open || today) : !open) return 0;
    const token = await getToken(userId);
    if (!token) return 0;
    await send(token, title, body, {
      type: `shift_punch_${kind}`,
      shiftId,
      date,
      collapseKey: `shift-${shiftId}-${date}-${kind}`,
    });
    return 1;
  };

  const ids = shift.userIds || [];
  let sent = 0;
  for (let i = 0; i < ids.length; i += 10) {
    const results = await Promise.all(ids.slice(i, i + 10).map((u) =>
      remind(u).catch((err) => {
        log.error(`[shifts] reminder failed for ${u}:`, err.message);
        return 0;
      })));
    sent += results.reduce((a, b) => a + b, 0);
  }
  log.log(`[shifts] ${kind} reminder for ${code}/${shiftId}: ${sent} of ${ids.length} notified`);
  return sent;
}

module.exports = { queueShiftTasks, makeShiftData, runShiftReminder };
