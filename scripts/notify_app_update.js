#!/usr/bin/env node
/**
 * One-time "please update TrackFolks" push to everyone NOT on the latest build.
 *
 *   node scripts/notify_app_update.js                 # dry run: who WOULD get it
 *   node scripts/notify_app_update.js --send          # actually send
 *   node scripts/notify_app_update.js --code TKSV63   # limit to one org code
 *
 * Who gets it: every user with an FCM token whose Users-doc `appBuild` is
 * missing (builds that predate version reporting are assumed old) or lower than
 * Config/app.<platform>.latestBuild. A user with no `platform` recorded is
 * necessarily one with no `appBuild`, so is always included.
 *
 * Config/app (server-only doc, create it in the Firebase console):
 *   android: { latestBuild: 17, minBuild: 0, storeUrl: "https://play.google.com/store/apps/details?id=com.agoriya.app" }
 *   ios:     { latestBuild: 17, minBuild: 0, storeUrl: "https://apps.apple.com/app/id..." }
 *
 * The push carries both store links and the app picks its own on tap
 * (main.dart `app_update`). Builds that predate that handler open the app
 * instead of the store — so the text names the store to use.
 *
 * Auth: Application Default Credentials (`gcloud auth application-default login`),
 * project agoriya-app. Uses firebase-admin from functions/node_modules.
 */
const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

const args = process.argv.slice(2);
const SEND = args.includes("--send");
const codeIdx = args.indexOf("--code");
const ORG_CODE = codeIdx >= 0 ? (args[codeIdx + 1] || "").toUpperCase() : null;
if (codeIdx >= 0 && !ORG_CODE) {
  console.error("--code needs a value");
  process.exit(1);
}

admin.initializeApp({ projectId: "agoriya-app" });
const db = admin.firestore();

(async () => {
  const cfgSnap = await db.collection("Config").doc("app").get();
  if (!cfgSnap.exists) {
    console.error("Config/app does not exist. Create it first (see the header of this file).");
    process.exit(1);
  }
  const cfg = cfgSnap.data();
  const latest = {
    android: Number((cfg.android || {}).latestBuild || 0),
    ios: Number((cfg.ios || {}).latestBuild || 0),
  };
  if (!latest.android && !latest.ios) {
    console.error("Config/app has no latestBuild for either platform — nothing to compare against.");
    process.exit(1);
  }
  const androidUrl = (cfg.android || {}).storeUrl || "";
  const iosUrl = (cfg.ios || {}).storeUrl || "";
  console.log(`Latest builds → android: ${latest.android || "(unset)"}, ios: ${latest.ios || "(unset)"}`);

  const query = ORG_CODE ? db.collection("Users").where("code", "==", ORG_CODE) : db.collection("Users");
  const users = await query.get();

  const targets = [];
  const skipped = { noToken: 0, upToDate: 0 };
  for (const d of users.docs) {
    const u = d.data();
    if (!u.fcmToken) { skipped.noToken++; continue; }
    const build = typeof u.appBuild === "number" ? u.appBuild : null;
    const platform = u.platform === "ios" || u.platform === "android" ? u.platform : null;
    // Unknown build, or unknown platform: assume old. Known build: compare
    // with that platform's latest (a platform with no latestBuild is skipped).
    const isOld = build === null || platform === null || build < latest[platform];
    if (!isOld) { skipped.upToDate++; continue; }
    targets.push({
      id: d.id,
      name: `${u.firstName || ""} ${u.lastName || ""}`.trim(),
      token: u.fcmToken,
      build,
      platform,
    });
  }

  console.log(`Users scanned: ${users.size} | to notify: ${targets.length} | ` +
    `already latest: ${skipped.upToDate} | no FCM token: ${skipped.noToken}`);
  const unknown = targets.filter((t) => t.build === null).length;
  console.log(`  of those, build unknown (old/unreported): ${unknown}, known-but-old: ${targets.length - unknown}`);

  if (!SEND) {
    targets.slice(0, 40).forEach((t) => console.log(`  - ${t.name} [${t.platform || "?"} build ${t.build ?? "?"}]`));
    if (targets.length > 40) console.log(`  … and ${targets.length - 40} more`);
    console.log("\nDry run — nothing sent. Re-run with --send to send.");
    return;
  }

  const notification = {
    title: "Update TrackFolks",
    body: "A new version of TrackFolks is available. Please update it from the " +
      "Play Store (Android) or App Store (iPhone) for reliable tracking.",
  };
  const data = { type: "app_update", androidUrl, iosUrl };

  let ok = 0;
  const failed = [];
  for (let i = 0; i < targets.length; i += 500) {
    const chunk = targets.slice(i, i + 500);
    const res = await admin.messaging().sendEach(chunk.map((t) => ({
      token: t.token,
      notification,
      data,
      android: { priority: "high" },
    })));
    res.responses.forEach((r, idx) => {
      if (r.success) ok++;
      else failed.push(`${chunk[idx].name} (${chunk[idx].id}): ${r.error && r.error.code}`);
    });
  }
  console.log(`Sent: ${ok} | failed: ${failed.length}`);
  failed.forEach((f) => console.log("  ! " + f));
})().catch((e) => { console.error(e.message); process.exit(1); });
