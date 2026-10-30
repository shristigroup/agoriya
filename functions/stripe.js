// Stripe payments for TrackFolks organisations (one-time yearly payment, no auto-renewal).
//   createCheckoutSession: the website sends { code, users }; we price it, and return a Stripe Checkout URL.
//   stripeWebhook:         Stripe confirms the payment; we raise the organisation's user limit.
// Secrets (never in git):  firebase functions:secrets:set STRIPE_SECRET_KEY   and   STRIPE_WEBHOOK_SECRET
const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const Stripe = require("stripe");
const { FREE_USERS, MAX_USERS, planAmountCents } = require("./plan");

const stripeKey = defineSecret("STRIPE_SECRET_KEY");
const webhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");

const SITE = "https://tf.shristigroup.com";
const ALLOWED_ORIGINS = [SITE, "http://localhost:8000"];
const REGION = "asia-south1";

exports.createCheckoutSession = onRequest(
  { region: REGION, cors: ALLOWED_ORIGINS, secrets: [stripeKey] },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }
    const db = admin.firestore();
    const code = String((req.body && req.body.code) || "").trim().toUpperCase();
    const users = Number(req.body && req.body.users);
    const dryRun = !!(req.body && req.body.dryRun);

    if (!/^[A-Z0-9]{6}$/.test(code)) { res.status(400).json({ error: "Enter your 6-character organisation code." }); return; }
    if (Number.isInteger(users) && users > MAX_USERS) {
      res.status(400).json({ custom: true, error: `For more than ${MAX_USERS} users we prepare a custom quote. Please email developer@shristigroup.com with your organisation code and team size.` });
      return;
    }
    if (!Number.isInteger(users) || users <= FREE_USERS) {
      res.status(400).json({ error: `Enter a team size above ${FREE_USERS}. The first ${FREE_USERS} users are free.` });
      return;
    }
    const codeDoc = await db.collection("Codes").doc(code).get();
    if (!codeDoc.exists) { res.status(404).json({ error: "We could not find that organisation code." }); return; }
    const data = codeDoc.data();
    const firstYear = !data.paidUntil; // no earlier payment: first-year cap applies
    const amountCents = planAmountCents(users, firstYear);
    const testMode = stripeKey.value().startsWith("sk_test");
    const quote = { code, users, firstYear, amountCents, currentLimit: data.totalUserCount || FREE_USERS, testMode };
    if (dryRun) { res.status(200).json(quote); return; }

    const stripe = new Stripe(stripeKey.value());
    const description = `TrackFolks for organisation ${code}: ${users} users for one year`;
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      client_reference_id: code,
      line_items: [{
        quantity: 1,
        price_data: {
          currency: "usd",
          unit_amount: amountCents,
          product_data: {
            name: `TrackFolks yearly plan (${firstYear ? "first year" : "renewal"})`,
            description,
          },
        },
      }],
      metadata: { code, users: String(users), firstYear: String(firstYear) },
      invoice_creation: { enabled: true, invoice_data: { description, metadata: { code, users: String(users) } } },
      custom_text: { submit: { message: `Refunds: full refund if requested within 15 days of payment; after that, pro-rata for the unused days less Stripe's processing fee. Details: ${SITE}/refund/` } },
      success_url: `${SITE}/payment/success.html?code=${code}`,
      cancel_url: `${SITE}/payment/cancelled.html`,
    });
    res.status(200).json({ ...quote, url: session.url });
  }
);

exports.stripeWebhook = onRequest(
  { region: REGION, secrets: [stripeKey, webhookSecret] },
  async (req, res) => {
    const stripe = new Stripe(stripeKey.value());
    let event;
    try {
      event = stripe.webhooks.constructEvent(req.rawBody, req.headers["stripe-signature"], webhookSecret.value());
    } catch (err) {
      console.error("[stripeWebhook] bad signature:", err.message);
      res.status(400).send("Invalid signature");
      return;
    }
    if (event.type !== "checkout.session.completed") { res.status(200).json({ ignored: event.type }); return; }

    const session = event.data.object;
    if (session.payment_status !== "paid") { res.status(200).json({ ignored: "not paid" }); return; }
    const db = admin.firestore();

    // Stripe can deliver an event more than once: process each event id a single time.
    try {
      await db.collection("StripeEvents").doc(event.id).create({ type: event.type, at: admin.firestore.FieldValue.serverTimestamp() });
    } catch (err) {
      if (err.code === 6) { res.status(200).json({ duplicate: true }); return; } // ALREADY_EXISTS
      throw err;
    }

    const { code, users, firstYear } = session.metadata || {};
    const seats = Number(users);
    if (!code || !Number.isInteger(seats)) { console.error("[stripeWebhook] missing metadata on", session.id); res.status(200).json({ error: "metadata" }); return; }

    const codeRef = db.collection("Codes").doc(code);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(codeRef);
      if (!snap.exists) { console.error("[stripeWebhook] code not found:", code); return; }
      const d = snap.data();
      const now = new Date();
      const start = d.paidUntil && d.paidUntil.toDate() > now ? d.paidUntil.toDate() : now; // a renewal paid early extends the current period
      const until = new Date(start);
      until.setFullYear(until.getFullYear() + 1);
      tx.update(codeRef, {
        totalUserCount: Math.max(d.totalUserCount || FREE_USERS, seats),
        paidUntil: admin.firestore.Timestamp.fromDate(until),
        lastPaymentId: session.id,
      });
      tx.set(db.collection("Payments").doc(session.id), {
        code, users: seats, firstYear: firstYear === "true", amountCents: session.amount_total, currency: session.currency,
        email: (session.customer_details && session.customer_details.email) || null,
        paidAt: admin.firestore.FieldValue.serverTimestamp(), eventId: event.id,
      });
    });
    console.log(`[stripeWebhook] ${code} now allows ${seats} users (payment ${session.id})`);
    res.status(200).json({ ok: true });
  }
);
