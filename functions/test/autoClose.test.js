const test = require("node:test");
const assert = require("node:assert/strict");
const { classifyAutoClose, isDeadTokenError, ACK_MIN_BUILD } = require("../autoClose");

const ts = (ms) => ({ toMillis: () => ms });
const newApp = { appBuild: ACK_MIN_BUILD };

test("a dead token wins over everything else", () => {
  assert.equal(
    classifyAutoClose({ tracking: {}, user: newApp, tokenState: "unregistered" }),
    "token_unregistered");
});

test("no token on file", () => {
  assert.equal(
    classifyAutoClose({ tracking: {}, user: newApp, tokenState: "missing" }),
    "no_fcm_token");
});

test("builds before wake-up receipts cannot say whether it arrived", () => {
  for (const user of [{}, { appBuild: 16 }, null]) {
    assert.equal(classifyAutoClose({ tracking: {}, user, tokenState: "ok" }),
      "app_without_wakeup_ack");
  }
});

test("no receipt from a build that reports them = not received", () => {
  assert.equal(
    classifyAutoClose({ tracking: { watchdogPingedAt: ts(1000) }, user: newApp, tokenState: "ok" }),
    "wakeup_not_received");
});

test("a receipt from before this ping does not count", () => {
  assert.equal(
    classifyAutoClose({
      tracking: { watchdogPingedAt: ts(5000), wakeupReceivedAt: ts(1000), wakeupResult: "restarted" },
      user: newApp, tokenState: "ok" }),
    "wakeup_not_received");
});

test("received but restart failed", () => {
  assert.equal(
    classifyAutoClose({
      tracking: { watchdogPingedAt: ts(1000), wakeupReceivedAt: ts(2000), wakeupResult: "failed: boom" },
      user: newApp, tokenState: "ok" }),
    "wakeup_received_restart_failed");
});

test("restarted but no heartbeat followed", () => {
  assert.equal(
    classifyAutoClose({
      tracking: { watchdogPingedAt: ts(1000), wakeupReceivedAt: ts(2000), wakeupResult: "restarted" },
      user: newApp, tokenState: "ok" }),
    "wakeup_received_no_heartbeat");
});

test("received but never finished", () => {
  assert.equal(
    classifyAutoClose({
      tracking: { watchdogPingedAt: ts(1000), wakeupReceivedAt: ts(2000), wakeupResult: "received" },
      user: newApp, tokenState: "ok" }),
    "wakeup_received_not_completed");
});

test("only permanent FCM errors count as a dead token", () => {
  assert.equal(isDeadTokenError({ code: "messaging/registration-token-not-registered" }), true);
  assert.equal(isDeadTokenError({ code: "messaging/invalid-registration-token" }), true);
  assert.equal(isDeadTokenError({ code: "messaging/server-unavailable" }), false);
  assert.equal(isDeadTokenError(new Error("network")), false);
  assert.equal(isDeadTokenError(null), false);
});
