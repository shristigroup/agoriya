// Reminder sending and task queueing. The first groups use plain fakes; the last
// runs the real Firestore queries against the emulator (skipped when none is
// running, so a plain `node --test` still passes). Run all of it with:
//   npm run test:emulator
const test = require("node:test");
const assert = require("node:assert/strict");
const admin = require("firebase-admin");
const { queueShiftTasks, makeShiftData, runShiftReminder } = require("../shiftJobs");
const { atMinute } = require("../shifts");

const quiet = { log() {}, error() {} };
const ist = (date, hh, mm) => atMinute(date, hh * 60 + mm);

// ─── queueShiftTasks ─────────────────────────────────────────────────────────

test("queues a task for the start and one before the end, with a unique id", async () => {
  const calls = [];
  const enqueue = async (payload, opts) => calls.push({ payload, opts });
  const shift = { startMinute: 9 * 60, endMinute: 17 * 60 };
  const n = await queueShiftTasks({
    enqueue, code: "ORG", shiftId: "s1", shift, dateStr: "2026-11-28",
    now: ist("2026-11-28", 0, 0), log: quiet });
  assert.equal(n, 2);
  assert.deepEqual(calls.map((c) => c.payload.kind), ["in", "out"]);
  assert.equal(calls[0].opts.scheduleTime.getTime(), ist("2026-11-28", 9, 0).getTime());
  assert.equal(calls[1].opts.scheduleTime.getTime(), ist("2026-11-28", 16, 50).getTime());
  assert.equal(calls[0].opts.id, `s1-2026-11-28-in-${ist("2026-11-28", 9, 0).getTime()}`);
  assert.deepEqual(calls[0].payload, {
    code: "ORG", shiftId: "s1", kind: "in", date: "2026-11-28",
    expectedAt: ist("2026-11-28", 9, 0).getTime() });
});

test("a second run of the midnight job is harmless: 'already exists' is not an error", async () => {
  const errors = [];
  const enqueue = async () => { const e = new Error("Task already exists"); e.code = "functions/task-already-exists"; throw e; };
  const n = await queueShiftTasks({
    enqueue, code: "ORG", shiftId: "s1", shift: { startMinute: 600 }, dateStr: "2026-11-28",
    now: ist("2026-11-28", 0, 0), log: { error: (...a) => errors.push(a) } });
  assert.equal(n, 0);
  assert.equal(errors.length, 0);
});

test("any other queueing error is logged, and the next reminder is still queued", async () => {
  const errors = [];
  let first = true;
  const queued = [];
  const enqueue = async (payload) => {
    if (first) { first = false; throw new Error("quota exceeded"); }
    queued.push(payload.kind);
  };
  const n = await queueShiftTasks({
    enqueue, code: "ORG", shiftId: "s1", shift: { startMinute: 540, endMinute: 1020 },
    dateStr: "2026-11-28", now: ist("2026-11-28", 0, 0), log: { error: (...a) => errors.push(a) } });
  assert.equal(n, 1);
  assert.deepEqual(queued, ["out"]);
  assert.match(errors[0].join(" "), /could not queue in/);
});

test("nothing is queued for a place-only shift or for reminders over an hour late", async () => {
  const enqueue = async () => assert.fail("should not queue");
  assert.equal(await queueShiftTasks({ enqueue, code: "O", shiftId: "s", shift: { inLocation: {} },
    dateStr: "2026-11-28", now: ist("2026-11-28", 0, 0), log: quiet }), 0);
  assert.equal(await queueShiftTasks({ enqueue, code: "O", shiftId: "s", shift: { startMinute: 540 },
    dateStr: "2026-11-28", now: ist("2026-11-28", 11, 0), log: quiet }), 0);
});

// ─── runShiftReminder, with plain fakes ──────────────────────────────────────

const DAY = "2026-11-28";
function fakes({ shift, sessions = {}, tokens = {} }) {
  const sent = [];
  return {
    sent,
    deps: {
      getShift: async () => shift,
      getSessions: async (u) => { if (sessions[u] instanceof Error) throw sessions[u]; return sessions[u] || []; },
      getToken: async (u) => (u in tokens ? tokens[u] : `token-${u}`),
      send: async (token, title, body, data) => sent.push({ token, title, body, data }),
      log: quiet,
    },
  };
}
const job = (kind, shift) => ({
  code: "ORG", shiftId: "s1", kind, date: DAY,
  expectedAt: kind === "in" ? ist(DAY, 9, 0).getTime() : ist(DAY, 17, 50).getTime(),
});
const dayShift = { name: "Morning", startMinute: 540, endMinute: 1080, userIds: ["a", "b", "c", "d"] };

test("punch-in reminder: only people with no session today and none open", async () => {
  const { sent, deps } = fakes({
    shift: dayShift,
    sessions: {
      b: [{ id: `${DAY}_09:02:00`, isPunchedIn: true }],          // already punched in today
      c: [{ id: "2026-11-27_22:00:00", isPunchedIn: true }],      // still open from last night
      d: [{ id: "2026-11-27_09:00:00", isPunchedIn: false }],     // worked yesterday, not today
    },
  });
  const n = await runShiftReminder({ data: job("in"), ...deps });
  assert.equal(n, 2);
  assert.deepEqual(sent.map((s) => s.token).sort(), ["token-a", "token-d"]);
  assert.equal(sent[0].title, "Time to punch in");
  assert.equal(sent[0].body, "Morning shift");
  assert.equal(sent[0].data.type, "shift_punch_in");
  assert.equal(sent[0].data.collapseKey, `shift-s1-${DAY}-in`);
});

test("punch-out reminder: only people whose session is still open", async () => {
  const { sent, deps } = fakes({
    shift: dayShift,
    sessions: {
      a: [{ id: `${DAY}_09:00:00`, isPunchedIn: true }],
      b: [{ id: `${DAY}_09:00:00`, isPunchedIn: false }],
    },
  });
  const n = await runShiftReminder({ data: job("out"), ...deps });
  assert.equal(n, 1);
  assert.equal(sent[0].token, "token-a");
  assert.equal(sent[0].data.type, "shift_punch_out");
});

test("people without a push token are skipped, and one failure does not stop the others", async () => {
  const { sent, deps } = fakes({
    shift: dayShift,
    sessions: { b: new Error("read failed") },
    tokens: { c: null },
  });
  const n = await runShiftReminder({ data: job("in"), ...deps });
  assert.equal(n, 2); // a and d
  assert.deepEqual(sent.map((s) => s.token).sort(), ["token-a", "token-d"]);
});

test("a deleted shift, or one edited after the task was queued, sends nothing", async () => {
  const gone = fakes({ shift: null });
  assert.equal(await runShiftReminder({ data: job("in"), ...gone.deps }), 0);
  const edited = fakes({ shift: { ...dayShift, startMinute: 10 * 60 } });
  assert.equal(await runShiftReminder({ data: job("in"), ...edited.deps }), 0);
  assert.equal(gone.sent.length + edited.sent.length, 0);
});

test("a night shift's punch-out reminder the next morning finds the session from last night", async () => {
  const night = { name: "Night", startMinute: 22 * 60, endMinute: 6 * 60, endNextDay: true, userIds: ["a"] };
  const { sent, deps } = fakes({
    shift: night,
    sessions: { a: [{ id: "2026-11-28_22:05:00", isPunchedIn: true }] },
  });
  const data = { code: "ORG", shiftId: "s1", kind: "out", date: "2026-11-28",
    expectedAt: ist("2026-11-29", 5, 50).getTime() };
  assert.equal(await runShiftReminder({ data, ...deps }), 1);
  assert.equal(sent[0].data.date, "2026-11-28");
});

// ─── The real Firestore reads, against the emulator ──────────────────────────

const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const skip = emulator ? false : "no Firestore emulator (run: npm run test:emulator)";

test("reminders read real sessions and tokens correctly (emulator)", { skip }, async () => {
  if (!admin.apps.length) admin.initializeApp({ projectId: "demo-agoriya" });
  const db = admin.firestore();
  await fetch(`http://${emulator}/emulator/v1/projects/demo-agoriya/databases/(default)/documents`, { method: "DELETE" });

  const put = (path, data) => db.doc(path).set(data);
  await put("Codes/ORG/Shifts/s1", dayShift);
  for (const u of ["a", "b", "c", "d"]) await put(`Users/${u}`, { fcmToken: `token-${u}` });
  await put("Users/d", {});                                            // d has no token
  await put(`Users/b/Tracking/${DAY}_09:02:00`, { isPunchedIn: true });   // today
  await put("Users/c/Tracking/2026-11-27_22:00:00", { isPunchedIn: true }); // open from last night
  await put("Users/a/Tracking/2026-11-20_09:00:00", { isPunchedIn: false }); // old session, ignored

  const sent = [];
  const data = makeShiftData(db);
  const n = await runShiftReminder({ data: job("in"), ...data,
    send: async (token) => sent.push(token), log: quiet });
  assert.equal(n, 1);
  assert.deepEqual(sent, ["token-a"]); // b worked today, c is open, d has no token

  // and the punch-out side: only c has an open session, and it started last night
  const sentOut = [];
  await runShiftReminder({ data: job("out"), ...data,
    send: async (token) => sentOut.push(token), log: quiet });
  assert.deepEqual(sentOut.sort(), ["token-b", "token-c"]);
});
