// Who may start (or reopen) a Tracking session: only an app build at or above
// Config/app.<platform>.minBuild. Everything else about Tracking is unchanged.
const { test, before, after, beforeEach } = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc, updateDoc, deleteDoc, serverTimestamp } = require("firebase/firestore");

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-agoriya",
    firestore: { rules: fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8") },
  });
});
after(async () => env && env.cleanup());

const ANDROID_MIN_20 = { android: { minBuild: 20, latestBuild: 20 } };

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "Config/app"), ANDROID_MIN_20);
    // appBuild/platform are what the app writes to its own user document
    await setDoc(doc(db, "Users/current"), { uid: "u1", platform: "android", appBuild: 20, managers: ["boss"] });
    await setDoc(doc(db, "Users/low"), { uid: "u2", platform: "android", appBuild: 19, managers: [] });
    await setDoc(doc(db, "Users/old"), { uid: "u3", managers: [] });                       // a build that never reported
    await setDoc(doc(db, "Users/oldios"), { uid: "u4", managers: [] });
    await setDoc(doc(db, "Users/ios"), { uid: "u5", platform: "ios", appBuild: 20, managers: [] });
    await setDoc(doc(db, "Users/boss"), { uid: "u9", managers: [] });
    // an open session and a closed one for the old-build user
    await setDoc(doc(db, "Users/old/Tracking/open"), { isPunchedIn: true, distance: 0 });
    await setDoc(doc(db, "Users/old/Tracking/closed"), { isPunchedIn: false, distance: 0 });
    await setDoc(doc(db, "Users/current/Tracking/closed"), { isPunchedIn: false, distance: 0 });
  });
});

const as = (userId) => env.authenticatedContext("auth-" + userId, { userId }).firestore();
const session = () => ({ isPunchedIn: true, distance: 0, startTime: serverTimestamp() });

test("a current build can start a session", async () => {
  await assertSucceeds(setDoc(doc(as("current"), "Users/current/Tracking/new1"), session()));
});

test("a build that never reported its version cannot start a session", async () => {
  await assertFails(setDoc(doc(as("old"), "Users/old/Tracking/new1"), session()));
});

test("a build below minBuild cannot start a session", async () => {
  await assertFails(setDoc(doc(as("low"), "Users/low/Tracking/new1"), session()));
});

test("a platform with no minBuild is not enforced (old iOS builds)", async () => {
  await assertSucceeds(setDoc(doc(as("ios"), "Users/ios/Tracking/new1"), session()));
  // an old iOS build reports no platform, so it is judged as Android: blocked.
  await assertFails(setDoc(doc(as("oldios"), "Users/oldios/Tracking/new1"), session()));
});

test("minBuild 0 lets an old build through: a missing appBuild is just 0, not an error", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "Config/app"), { android: { minBuild: 0 } }));
  await assertSucceeds(setDoc(doc(as("old"), "Users/old/Tracking/new1"), session()));
});

test("no Config/app means no enforcement", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => deleteDoc(doc(ctx.firestore(), "Config/app")));
  await assertSucceeds(setDoc(doc(as("old"), "Users/old/Tracking/new1"), session()));
});

test("an old build still updates and closes a session it already has open", async () => {
  const ref = doc(as("old"), "Users/old/Tracking/open");
  await assertSucceeds(updateDoc(ref, { locationHeartbeatTimestamp: serverTimestamp() }));
  await assertSucceeds(updateDoc(ref, { distance: 3.2, locations: [] }));
  await assertSucceeds(updateDoc(ref, { isPunchedIn: false, stopTime: serverTimestamp() }));
});

test("reopening a closed session needs a current build", async () => {
  await assertFails(updateDoc(doc(as("old"), "Users/old/Tracking/closed"), { isPunchedIn: true }));
  await assertSucceeds(updateDoc(doc(as("current"), "Users/current/Tracking/closed"), { isPunchedIn: true }));
});

test("a manager can still read a team member's session; others cannot", async () => {
  await assertSucceeds(getDoc(doc(as("boss"), "Users/current/Tracking/closed")));
  await assertFails(getDoc(doc(as("low"), "Users/current/Tracking/closed")));
});

test("the owner can still delete their own session", async () => {
  await assertSucceeds(deleteDoc(doc(as("old"), "Users/old/Tracking/closed")));
});
