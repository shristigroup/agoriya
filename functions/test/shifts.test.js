const test = require("node:test");
const assert = require("node:assert/strict");
const {
  istDateString, addDays, atMinute, reminderTimes, dueTasks, isStale, anomalyText,
} = require("../shifts");

// 2026-11-28 in India time, as UTC instants.
const ist = (date, hh, mm) => atMinute(date, hh * 60 + mm);

test("istDateString reads the India date, including around midnight", () => {
  assert.equal(istDateString(new Date("2026-11-28T18:29:00Z")), "2026-11-28"); // 23:59 IST
  assert.equal(istDateString(new Date("2026-11-28T18:30:00Z")), "2026-11-29"); // 00:00 IST
  assert.equal(istDateString(new Date("2026-11-28T00:00:00Z")), "2026-11-28"); // 05:30 IST
});

test("addDays crosses month and year ends", () => {
  assert.equal(addDays("2026-11-30", 1), "2026-12-01");
  assert.equal(addDays("2026-12-31", 1), "2027-01-01");
});

test("a day shift: reminder at start, and 10 minutes before the end", () => {
  const shift = { startMinute: 9 * 60 + 30, endMinute: 18 * 60 };
  const t = reminderTimes(shift, "2026-11-28");
  assert.equal(t.in.getTime(), ist("2026-11-28", 9, 30).getTime());
  assert.equal(t.out.getTime(), ist("2026-11-28", 17, 50).getTime());
});

test("a night shift ends the next morning", () => {
  const shift = { startMinute: 22 * 60, endMinute: 6 * 60, endNextDay: true };
  const t = reminderTimes(shift, "2026-11-28");
  assert.equal(t.in.getTime(), ist("2026-11-28", 22, 0).getTime());
  assert.equal(t.out.getTime(), ist("2026-11-29", 5, 50).getTime());
});

test("a night shift ending at 00:05 pulls the reminder back into the previous day", () => {
  const shift = { startMinute: 18 * 60, endMinute: 5, endNextDay: true };
  const t = reminderTimes(shift, "2026-11-30");
  assert.equal(t.out.getTime(), ist("2026-11-30", 23, 55).getTime());
});

test("a location-only shift sends no reminders", () => {
  assert.deepEqual(reminderTimes({ inLocation: { lat: 1, lng: 2 } }, "2026-11-28"), {});
  assert.deepEqual(dueTasks({ name: "x" }, "2026-11-28", new Date()), []);
});

test("invalid minutes are ignored", () => {
  assert.deepEqual(reminderTimes({ startMinute: 1440, endMinute: -1 }, "2026-11-28"), {});
  assert.deepEqual(reminderTimes({ startMinute: "9" }, "2026-11-28"), {});
});

test("midnight job: a future reminder is queued at its time", () => {
  const shift = { startMinute: 9 * 60, endMinute: 17 * 60 };
  const now = ist("2026-11-28", 0, 0);
  const tasks = dueTasks(shift, "2026-11-28", now);
  assert.deepEqual(tasks.map((x) => x.kind), ["in", "out"]);
  assert.equal(tasks[0].scheduleTime.getTime(), ist("2026-11-28", 9, 0).getTime());
  assert.equal(tasks[1].scheduleTime.getTime(), ist("2026-11-28", 16, 50).getTime());
});

test("a shift right at midnight runs a few minutes late rather than not at all", () => {
  const shift = { startMinute: 0, endMinute: 8 * 60 };
  const now = ist("2026-11-28", 0, 5);
  const [inTask] = dueTasks(shift, "2026-11-28", now);
  assert.equal(inTask.kind, "in");
  assert.equal(inTask.scheduleTime.getTime(), now.getTime());
  assert.equal(inTask.expectedAt, ist("2026-11-28", 0, 0).getTime());
});

test("a reminder more than an hour late is skipped", () => {
  const shift = { startMinute: 9 * 60 };
  assert.equal(dueTasks(shift, "2026-11-28", ist("2026-11-28", 10, 1)).length, 0);
  assert.equal(dueTasks(shift, "2026-11-28", ist("2026-11-28", 9, 59)).length, 1);
});

test("a shift edited after queueing makes the old task stale", () => {
  const before = { startMinute: 9 * 60 };
  const expectedAt = reminderTimes(before, "2026-11-28").in.getTime();
  assert.equal(isStale(before, "2026-11-28", "in", expectedAt), false);
  assert.equal(isStale({ startMinute: 10 * 60 }, "2026-11-28", "in", expectedAt), true);
  assert.equal(isStale({}, "2026-11-28", "in", expectedAt), true);
  assert.equal(isStale({ startMinute: 9 * 60 }, "2026-11-28", "out", expectedAt), true);
});

test("anomaly text for the manager", () => {
  assert.equal(anomalyText(null), "");
  assert.equal(anomalyText({}), "");
  assert.equal(anomalyText({ lateMinutes: 12 }), "12 min late");
  assert.equal(
    anomalyText({ lateMinutes: 12, distanceM: 350, locationName: "HQ" }),
    "12 min late, 350 m from HQ");
  assert.equal(anomalyText({ distanceM: 2340, locationName: "HQ" }), "2.3 km from HQ");
  assert.equal(anomalyText({ distanceM: 150 }), "150 m from the location");
  assert.equal(anomalyText({ earlyMinutes: 30 }), "30 min early");
});
