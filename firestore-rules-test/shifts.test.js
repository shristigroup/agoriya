// Shifts (owner writes, org members read), the AI assistant's read-only config,
// and its per-day credit counter (+1 at a time, capped by Config/assistant).
const { test, before, after, beforeEach } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const { initializeTestEnvironment, assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc, updateDoc, deleteDoc } = require("firebase/firestore");

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-agoriya",
    firestore: { rules: fs.readFileSync(path.join(__dirname, "..", "firestore.rules"), "utf8") },
  });
});
after(async () => env && env.cleanup());

const as = (userId) => env.authenticatedContext("auth-" + userId, { userId }).firestore();
const ist = () => new Date(Date.now() + 330 * 60000).toISOString().slice(0, 10);
const shift = (extra = {}) => ({ name: "Morning", startMinute: 540, endMinute: 1080, userIds: ["member"], ...extra });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "Codes/ORG1"), { userId: "owner", totalUserCount: 10 });
    await setDoc(doc(db, "Users/owner"), { uid: "u1", code: "ORG1", managers: [] });
    await setDoc(doc(db, "Users/member"), { uid: "u2", code: "ORG1", managers: ["owner"] });
    await setDoc(doc(db, "Users/stranger"), { uid: "u3", code: "OTHER", managers: [] });
    await setDoc(doc(db, "Config/assistant"), { dailyCredits: 3 });
    await setDoc(doc(db, "Codes/ORG1/Shifts/s1"), shift());
  });
});

// ─── Shifts ──────────────────────────────────────────────────────────────────

test("the code's owner can create, edit and delete a shift", async () => {
  const db = as("owner");
  await assertSucceeds(setDoc(doc(db, "Codes/ORG1/Shifts/s2"), shift({ name: "Evening" })));
  await assertSucceeds(updateDoc(doc(db, "Codes/ORG1/Shifts/s2"), { endMinute: 1200 }));
  await assertSucceeds(deleteDoc(doc(db, "Codes/ORG1/Shifts/s2")));
});

test("an org member can read shifts but not change them", async () => {
  const db = as("member");
  await assertSucceeds(getDoc(doc(db, "Codes/ORG1/Shifts/s1")));
  await assertFails(updateDoc(doc(db, "Codes/ORG1/Shifts/s1"), { userIds: [] }));
  await assertFails(setDoc(doc(db, "Codes/ORG1/Shifts/s2"), shift()));
  await assertFails(deleteDoc(doc(db, "Codes/ORG1/Shifts/s1")));
});

test("someone from another org cannot read or write shifts", async () => {
  const db = as("stranger");
  await assertFails(getDoc(doc(db, "Codes/ORG1/Shifts/s1")));
  await assertFails(setDoc(doc(db, "Codes/ORG1/Shifts/s2"), shift()));
});

test("a signed-out caller cannot read shifts", async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "Codes/ORG1/Shifts/s1")));
});

test("a shift must have sensible fields", async () => {
  const db = as("owner");
  await assertFails(setDoc(doc(db, "Codes/ORG1/Shifts/bad1"), shift({ startMinute: 1440 })));
  await assertFails(setDoc(doc(db, "Codes/ORG1/Shifts/bad2"), shift({ endMinute: -1 })));
  await assertFails(setDoc(doc(db, "Codes/ORG1/Shifts/bad3"), shift({ radiusM: 5 })));
  await assertFails(setDoc(doc(db, "Codes/ORG1/Shifts/bad4"), shift({ evil: true })));
  // a location-only shift (no times) is fine
  await assertSucceeds(setDoc(doc(db, "Codes/ORG1/Shifts/ok"), {
    name: "Office", inLocation: { lat: 21.2, lng: 81.6, name: "HQ" }, radiusM: 100, userIds: [] }));
});

test("the Code doc itself stays read-only for the app", async () => {
  await assertSucceeds(getDoc(doc(as("stranger"), "Codes/ORG1")));
  await assertFails(updateDoc(doc(as("owner"), "Codes/ORG1"), { totalUserCount: 999 }));
});

// ─── Config/assistant ────────────────────────────────────────────────────────

test("a signed-in user can read Config/assistant but nobody can write it", async () => {
  await assertSucceeds(getDoc(doc(as("owner"), "Config/assistant")));
  await assertFails(updateDoc(doc(as("owner"), "Config/assistant"), { dailyCredits: 9999 }));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "Config/assistant")));
});

test("Config/app is still server-only", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), "Config/app"), { android: { minBuild: 1 } }));
  await assertFails(getDoc(doc(as("owner"), "Config/app")));
});

// ─── Assistant credits ───────────────────────────────────────────────────────

const usage = (userId, date = ist()) => doc(as(userId), `AssistantLog/${userId}/Dates/${date}`);

test("credits start at 0 or 1 and go up by one", async () => {
  await assertSucceeds(setDoc(usage("owner"), { credits: 1, entries: [] }));
  await assertSucceeds(updateDoc(usage("owner"), { credits: 2 }));
  await assertSucceeds(updateDoc(usage("owner"), { credits: 3 }));
});

test("credits cannot jump by more than one, start above one, or go down", async () => {
  await assertFails(setDoc(usage("owner"), { credits: 2, entries: [] }));
  await assertSucceeds(setDoc(usage("owner"), { credits: 1, entries: [] }));
  await assertFails(updateDoc(usage("owner"), { credits: 3 }));
  await assertSucceeds(updateDoc(usage("owner"), { credits: 2 }));
  await assertFails(updateDoc(usage("owner"), { credits: 1 }));
});

test("credits stop at the limit in Config/assistant, and a changed limit applies at once", async () => {
  await assertSucceeds(setDoc(usage("owner"), { credits: 1, entries: [] }));
  await assertSucceeds(updateDoc(usage("owner"), { credits: 2 }));
  await assertSucceeds(updateDoc(usage("owner"), { credits: 3 }));
  await assertFails(updateDoc(usage("owner"), { credits: 4 }));
  await env.withSecurityRulesDisabled(async (ctx) => updateDoc(doc(ctx.firestore(), "Config/assistant"), { dailyCredits: 5 }));
  await assertSucceeds(updateDoc(usage("owner"), { credits: 4 }));
});

test("only today's usage doc can be written", async () => {
  await assertFails(setDoc(usage("owner", "2020-01-01"), { credits: 1, entries: [] }));
  await assertFails(setDoc(usage("owner", "2099-12-31"), { credits: 1, entries: [] }));
});

test("one user cannot touch another user's credits, and nobody can delete them", async () => {
  await assertSucceeds(setDoc(usage("owner"), { credits: 1, entries: [] }));
  await assertFails(setDoc(doc(as("member"), `AssistantLog/owner/Dates/${ist()}`), { credits: 0, entries: [] }));
  await assertFails(getDoc(doc(as("member"), `AssistantLog/owner/Dates/${ist()}`)));
  await assertSucceeds(getDoc(usage("owner")));
  await assertFails(deleteDoc(usage("owner")));
});

test("log entries can only be added, one at a time", async () => {
  await assertSucceeds(setDoc(usage("owner"), { credits: 0, entries: [] }));
  await assertSucceeds(updateDoc(usage("owner"), { entries: [{ kind: "declined", text: "rank my team" }] }));
  await assertFails(updateDoc(usage("owner"), { entries: [] }));
  await assertFails(updateDoc(usage("owner"), { entries: [{ a: 1 }, { b: 2 }, { c: 3 }] }));
  await assertFails(updateDoc(usage("owner"), { extra: 1 }));
});
