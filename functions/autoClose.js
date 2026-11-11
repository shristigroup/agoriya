// Why the watchdog gave up on a session. Pure, so it can be unit-tested
// (functions/test/autoClose.test.js).
//
// The watchdog records `autoClosedReason: "no_location_data"` for every
// auto-close (the app keys off that), and this adds `autoClosedDetail`, which
// says WHY the phone never resumed sending location, from what we know at the
// moment of closing:
//
//   token_unregistered            FCM said the device token is dead (app
//                                 uninstalled / data cleared) — nothing to wake.
//   no_fcm_token                  the user has no token on file.
//   app_without_wakeup_ack        the app build predates wake-up receipts
//                                 (appBuild < ACK_MIN_BUILD), so receipt is unknowable.
//   wakeup_not_received           a build that reports receipts never reported
//                                 this wake-up — FCM did not reach it in time.
//   wakeup_received_restart_failed  it received the wake-up but tracking would not restart.
//   wakeup_received_no_heartbeat  it restarted tracking, yet no heartbeat followed
//                                 within the window.
//   wakeup_received_not_completed it received the wake-up but never finished handling it.
//
// A wake-up that arrives AFTER the session was closed is not visible here (the
// receipt does not exist yet); it shows up later as wakeupReceivedAt > stopTime.

// First app build that writes wakeupReceivedAt / wakeupResult (2.2.0+17).
const ACK_MIN_BUILD = 17;

function millis(ts) {
  return ts && typeof ts.toMillis === "function" ? ts.toMillis() : null;
}

function classifyAutoClose({ tracking, user, tokenState }) {
  if (tokenState === "unregistered") return "token_unregistered";
  if (tokenState === "missing") return "no_fcm_token";

  const build = user && typeof user.appBuild === "number" ? user.appBuild : null;
  if (build === null || build < ACK_MIN_BUILD) return "app_without_wakeup_ack";

  const pingedAt = millis(tracking && tracking.watchdogPingedAt);
  const receivedAt = millis(tracking && tracking.wakeupReceivedAt);
  if (receivedAt === null || (pingedAt !== null && receivedAt < pingedAt)) {
    return "wakeup_not_received";
  }

  const result = (tracking && tracking.wakeupResult) || "";
  if (result.startsWith("failed")) return "wakeup_received_restart_failed";
  if (result === "restarted") return "wakeup_received_no_heartbeat";
  return "wakeup_received_not_completed";
}

// FCM errors that mean the token will never work again.
function isDeadTokenError(err) {
  const code = err && err.code;
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  );
}

module.exports = { classifyAutoClose, isDeadTokenError, ACK_MIN_BUILD };
