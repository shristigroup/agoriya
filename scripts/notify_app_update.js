#!/usr/bin/env node
/**
 * One-time "please update TrackFolks" push to everyone NOT on the latest build.
 *
 * Run it with no arguments to see the options. Nothing happens until you pick
 * a mode:
 *
 *   node scripts/notify_app_update.js --dry-run     # who WOULD get it, and the exact message; sends nothing
 *   node scripts/notify_app_update.js --send        # send (asks you to type "send" first)
 *
 * Options: --user <id> (one account, for testing on your own phone), --code <ORG>,
 * --title "...", --body "...", --url <url>, --yes. See the usage text below.
 *
 * The message is shown on a dry run too, so check it there first. Messages go
 * out one per user (not a topic broadcast), 10 at a time, and each user's
 * result is printed as it arrives.
 *
 * Who gets it: every user with an FCM token whose Users-doc `appBuild` is
 * missing (builds that predate version reporting are assumed old) or lower than
 * Config/app.<platform>.latestBuild. A user with no `platform` recorded is
 * necessarily one with no `appBuild`, so is always included.
 *
 * Config/app (server-only doc, create it in the Firebase console):
 *   android: { latestBuild: 20, minBuild: 0, storeUrl: "https://play.google.com/store/apps/details?id=com.agoriya.app" }
 *   ios:     { latestBuild: 20, minBuild: 0, storeUrl: "https://apps.apple.com/app/id..." }
 *   downloadUrl (optional): overrides the page the push opens.
 * (storeUrl is used by the punch-in version gate, not by this script.)
 *
 * Tapping the push opens the download page (DEFAULT_DOWNLOAD_URL), which has
 * both the Play Store and TestFlight buttons. Builds that predate the
 * `app_update` handler just open the app instead — so the text also names the
 * page, for them to type.
 *
 * Auth: Application Default Credentials (`gcloud auth application-default login`),
 * project agoriya-app. Uses firebase-admin from functions/node_modules.
 */
const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

const DEFAULT_DOWNLOAD_URL = "https://tf.shristigroup.com/#download";

const DEFAULT_TITLE = "Update TrackFolks";
const DEFAULT_BODY = "A new version of TrackFolks is available. Update it from the Play Store, " +
  "or open tf.shristigroup.com and tap Download.";
const BATCH = 10; // messages sent in parallel; progress is printed after each batch

const USAGE = `
TrackFolks update notification: one push per user, 10 at a time, progress printed as it goes.
Nothing is sent unless you pass --send.

Usage:
  node scripts/notify_app_update.js <mode> [options]

Modes (choose one):
  --dry-run          list who would get it and show the exact message; sends nothing
  --send             send it; asks you to type "send" first

Options:
  --user <id,id,..>  only these users, by Users document id, comma separated with no spaces,
                     e.g. ashish-sharma-+919538384545 (one id works too, handy for testing on your own
                     phone). Skips the "already on the latest build" check. An unknown id stops the run.
  --code <ORG>       only the users of this organisation code
  --title "<text>"   notification title (default: "${DEFAULT_TITLE}")
  --body "<text>"    notification text  (default: "${DEFAULT_BODY}")
  --url <url>        page a tap opens, on builds 3.0.0+20 and later (default: ${DEFAULT_DOWNLOAD_URL})
  --yes              with --send: skip the "type send" question
  --help             show this

Examples:
  node scripts/notify_app_update.js --dry-run
  node scripts/notify_app_update.js --send --user ashish-sharma-+919538384545 --title "Test" --body "Testing the update message"
  node scripts/notify_app_update.js --send
`;

const args = process.argv.slice(2);
// No arguments (or --help): show the options and stop. Never does any work by itself.
if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
  console.log(USAGE);
  process.exit(0);
}

const FLAGS_WITH_VALUE = ["--code", "--title", "--body", "--url", "--user"];
const FLAGS = [...FLAGS_WITH_VALUE, "--send", "--dry-run", "--yes"];
for (let i = 0; i < args.length; i++) {
  if (FLAGS_WITH_VALUE.includes(args[i])) { i++; continue; } // its value is checked by opt()
  if (!FLAGS.includes(args[i])) {
    // A typo such as --boddy must not silently send the default message.
    console.error(`Unknown argument "${args[i]}". Run with no arguments to see the options.`);
    process.exit(1);
  }
}
function opt(name) {
  const i = args.indexOf(name);
  if (i < 0) return null;
  const v = args[i + 1];
  if (v === undefined || v.startsWith("--") || !v.trim()) {
    console.error(`${name} needs a value`);
    process.exit(1);
  }
  return v;
}

const SEND = args.includes("--send");
const DRY_RUN = args.includes("--dry-run");
if (SEND === DRY_RUN) {
  console.error(SEND ? "Choose one mode, not both: --dry-run or --send." :
    "Choose a mode: --dry-run (preview, sends nothing) or --send.");
  console.error("Run with no arguments to see all the options.");
  process.exit(1);
}
const YES = args.includes("--yes");
const USER_IDS = [...new Set((opt("--user") || "").split(",").map((x) => x.trim()).filter(Boolean))];
if (args.includes("--user") && USER_IDS.length === 0) {
  // e.g. --user "," must not quietly fall back to messaging everyone.
  console.error("--user needs at least one user id.");
  process.exit(1);
}
const USER_MODE = USER_IDS.length > 0;
const ORG_CODE = (opt("--code") || "").toUpperCase() || null;
if (USER_MODE && ORG_CODE) {
  console.error("Use either --user or --code, not both.");
  process.exit(1);
}
const TITLE = opt("--title") || DEFAULT_TITLE;
const BODY = opt("--body") || DEFAULT_BODY;
const URL_OVERRIDE = opt("--url");

function confirm(question) {
  if (!process.stdin.isTTY) return Promise.resolve("");
  const rl = require("readline").createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (a) => { rl.close(); resolve(a.trim()); }));
}

admin.initializeApp({ projectId: "agoriya-app" });
const db = admin.firestore();

(async () => {
  const cfgSnap = await db.collection("Config").doc("app").get();
  // --user sends to one named account whatever its build, so it doesn't need the build numbers.
  if (!cfgSnap.exists && !USER_MODE) {
    console.error("Config/app does not exist. Create it first (see the header of this file).");
    process.exit(1);
  }
  const cfg = cfgSnap.exists ? cfgSnap.data() : {};
  const latest = {
    android: Number((cfg.android || {}).latestBuild || 0),
    ios: Number((cfg.ios || {}).latestBuild || 0),
  };
  if (!USER_MODE && !latest.android && !latest.ios) {
    console.error("Config/app has no latestBuild for either platform — nothing to compare against.");
    process.exit(1);
  }
  const downloadUrl = URL_OVERRIDE || cfg.downloadUrl || DEFAULT_DOWNLOAD_URL;
  if (!USER_MODE) {
    console.log(`Latest builds → android: ${latest.android || "(unset)"}, ios: ${latest.ios || "(unset)"}`);
  }

  let docs;
  if (USER_MODE) {
    docs = await Promise.all(USER_IDS.map((id) => db.collection("Users").doc(id).get()));
    const missing = USER_IDS.filter((id, i) => !docs[i].exists);
    if (missing.length) {
      // A typo in an id must stop the run, not be skipped quietly.
      console.error(`No user with id: ${missing.map((id) => `"${id}"`).join(", ")}. Nothing was sent.`);
      process.exit(1);
    }
  } else {
    const query = ORG_CODE ? db.collection("Users").where("code", "==", ORG_CODE) : db.collection("Users");
    docs = (await query.get()).docs;
  }

  const targets = [];
  const skipped = { noToken: 0, upToDate: 0 };
  for (const d of docs) {
    const u = d.data();
    if (!u.fcmToken) {
      if (USER_MODE) console.log(`Skipping ${d.id}: no push token (the app has not registered one).`);
      skipped.noToken++;
      continue;
    }
    const build = typeof u.appBuild === "number" ? u.appBuild : null;
    const platform = u.platform === "ios" || u.platform === "android" ? u.platform : null;
    // --user: always selected (that is what you asked for). Otherwise unknown build, or unknown platform: assume old.
    // Known build: compare with that platform's latest (a platform with no latestBuild is skipped).
    const isOld = USER_MODE || build === null || platform === null || build < latest[platform];
    if (!isOld) { skipped.upToDate++; continue; }
    targets.push({
      id: d.id,
      name: `${u.firstName || ""} ${u.lastName || ""}`.trim(),
      token: u.fcmToken,
      build,
      platform,
    });
  }

  if (USER_MODE) {
    console.log(`Selected ${targets.length} of ${USER_IDS.length} user${USER_IDS.length === 1 ? "" : "s"}:`);
    targets.forEach((t) => console.log(`  - ${t.name} (${t.id}) [${t.platform || "?"} build ${t.build ?? "?"}]`));
  } else {
    console.log(`Users scanned: ${docs.length} | to notify: ${targets.length} | ` +
      `already latest: ${skipped.upToDate} | no FCM token: ${skipped.noToken}`);
    const unknown = targets.filter((t) => t.build === null).length;
    console.log(`  of those, build unknown (old/unreported): ${unknown}, known-but-old: ${targets.length - unknown}`);
  }

  console.log("\nMessage (" + TITLE.length + " + " + BODY.length + " characters):");
  console.log(`  Title: ${TITLE}`);
  console.log(`  Body:  ${BODY}`);
  console.log(`  Tap:   opens ${downloadUrl} — only on builds that handle app_update; older builds just open the app`);
  console.log("  Plain notification: no action buttons.\n");

  if (targets.length === 0) {
    console.log("Nobody to notify.");
    return;
  }

  if (!SEND) {
    if (!USER_MODE) {
      targets.slice(0, 40).forEach((t) => console.log(`  - ${t.name} [${t.platform || "?"} build ${t.build ?? "?"}]`));
      if (targets.length > 40) console.log(`  … and ${targets.length - 40} more`);
    }
    console.log("\nDry run — nothing sent. Run again with --send (and the same options) to send.");
    return;
  }

  if (!YES) {
    const n = targets.length;
    const answer = await confirm(`Send this to ${n} ${n === 1 ? "user" : "users"} now? Type "send" to continue: `);
    if (answer !== "send") {
      console.log(process.stdin.isTTY ? "Cancelled — nothing sent." :
        "Not an interactive terminal — nothing sent. Add --yes to send without the question.");
      return;
    }
  }

  const notification = { title: TITLE, body: BODY };
  const data = { type: "app_update", url: downloadUrl };
  const width = String(targets.length).length;

  let ok = 0, done = 0;
  const failed = [];
  for (let i = 0; i < targets.length; i += BATCH) {
    const chunk = targets.slice(i, i + BATCH);
    const res = await admin.messaging().sendEach(chunk.map((t) => ({
      token: t.token,
      notification,
      data,
      android: { priority: "high" },
    })));
    res.responses.forEach((r, idx) => {
      done++;
      const t = chunk[idx];
      if (r.success) {
        ok++;
        console.log(`[${String(done).padStart(width)}/${targets.length}] sent    ${t.name}`);
      } else {
        const code = (r.error && r.error.code) || "unknown error";
        failed.push(`${t.name} (${t.id}): ${code}`);
        console.log(`[${String(done).padStart(width)}/${targets.length}] FAILED  ${t.name} — ${code}`);
      }
    });
  }
  console.log(`\nDone. Sent: ${ok} | failed: ${failed.length}`);
  failed.forEach((f) => console.log("  ! " + f));
})().catch((e) => { console.error(e.message); process.exit(1); });
