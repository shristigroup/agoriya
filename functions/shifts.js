// Pure helpers for shift reminders and anomaly text. Kept free of Firebase so
// they can be unit-tested (functions/test/shifts.test.js).
//
// A shift doc (Codes/{code}/Shifts/{id}) looks like:
//   { name, startMinute?, endMinute?, endNextDay?, userIds: [...],
//     inLocation?: {lat, lng, name, address}, outLocation?, radiusM }
// startMinute / endMinute are minutes after midnight, India time. A shift with
// no times (location only) sends no reminders.

const IST_OFFSET_MS = 330 * 60 * 1000;
// The punch-out reminder goes this long BEFORE the shift ends.
const OUT_LEAD_MINUTES = 10;
// A reminder that is already this late (scheduler outage, a shift edited just
// after its time) is no use any more and is skipped.
const MAX_LATE_MS = 60 * 60 * 1000;

const isMinute = (v) => Number.isInteger(v) && v >= 0 && v < 1440;

// "2026-11-28" for the given instant, as read on an India clock.
function istDateString(date) {
  return new Date(date.getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

function addDays(dateStr, n) {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// The instant that is `minute` minutes after midnight, India time, on dateStr.
function atMinute(dateStr, minute) {
  return new Date(Date.parse(`${dateStr}T00:00:00Z`) + minute * 60000 - IST_OFFSET_MS);
}

// When this shift's reminders are due for the shift day that STARTS on
// dateStr. A shift that ends next day (a night shift) has its punch-out
// reminder on the following morning.
function reminderTimes(shift, dateStr) {
  const times = {};
  if (isMinute(shift.startMinute)) times.in = atMinute(dateStr, shift.startMinute);
  if (isMinute(shift.endMinute)) {
    const endDay = shift.endNextDay ? addDays(dateStr, 1) : dateStr;
    times.out = new Date(
      atMinute(endDay, shift.endMinute).getTime() - OUT_LEAD_MINUTES * 60000);
  }
  return times;
}

// Tasks to queue now for the shift day starting on dateStr:
// [{ kind: "in" | "out", expectedAt: ms, scheduleTime: Date }].
function dueTasks(shift, dateStr, now) {
  const tasks = [];
  const times = reminderTimes(shift, dateStr);
  for (const kind of ["in", "out"]) {
    const at = times[kind];
    if (!at) continue;
    if (at.getTime() >= now.getTime()) {
      tasks.push({ kind, expectedAt: at.getTime(), scheduleTime: at });
    } else if (now.getTime() - at.getTime() <= MAX_LATE_MS) {
      tasks.push({ kind, expectedAt: at.getTime(), scheduleTime: now });
    }
  }
  return tasks;
}

// A queued task is stale if the shift was edited after it was queued: its
// expected time no longer matches the shift as it is now.
function isStale(shift, dateStr, kind, expectedAt) {
  const at = reminderTimes(shift, dateStr)[kind];
  return !at || Math.abs(at.getTime() - expectedAt) > 60 * 1000;
}

function formatDistance(m) {
  return m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${Math.round(m)} m`;
}

// One line for the manager: "12 min late, 350 m from HQ". Empty if none.
function anomalyText(a) {
  if (!a) return "";
  const parts = [];
  if (a.lateMinutes > 0) parts.push(`${a.lateMinutes} min late`);
  if (a.earlyMinutes > 0) parts.push(`${a.earlyMinutes} min early`);
  if (a.distanceM > 0) {
    parts.push(`${formatDistance(a.distanceM)} from ${a.locationName || "the location"}`);
  }
  return parts.join(", ");
}

module.exports = {
  OUT_LEAD_MINUTES, MAX_LATE_MS, istDateString, addDays, atMinute,
  reminderTimes, dueTasks, isStale, anomalyText,
};
