# Stripe payments

One-time yearly payment per organisation code. No auto-renewal: renewals are invoiced by hand.
Pricing (see `plan.js`): first 10 users free, then $12 per user per year, capped at $199 in the first year and $399 on renewal.

## Pieces
- `createCheckoutSession` (HTTPS): the website's pay box (`assets/js/checkout.js`) sends `{ code, users }`. Add `dryRun: true` for a quote only. Returns a Stripe Checkout URL.
- `stripeWebhook` (HTTPS): Stripe calls it on `checkout.session.completed`. It raises `Codes/{code}.totalUserCount`, sets `paidUntil` (one year, extended if renewed early), and records `Payments/{sessionId}`. Each event id is processed once (`StripeEvents`).
- `payment/success.html`, `payment/cancelled.html`: where Checkout sends the buyer.

## Setup (test mode first)
1. `firebase functions:secrets:set STRIPE_SECRET_KEY` (paste `sk_test_...` when asked; never commit it).
2. `firebase functions:secrets:set STRIPE_WEBHOOK_SECRET` with any placeholder for now.
3. `firebase deploy --only functions:createCheckoutSession,functions:stripeWebhook --project agoriya-app`
4. Stripe dashboard > Developers > Webhooks > Add endpoint: `https://asia-south1-agoriya-app.cloudfunctions.net/stripeWebhook`, event `checkout.session.completed`. Copy its signing secret (`whsec_...`).
5. `firebase functions:secrets:set STRIPE_WEBHOOK_SECRET` again with the real value, then redeploy `functions:stripeWebhook`.
6. Pay with test card `4242 4242 4242 4242` (any future date, any CVC) on the website; check the code's limit in Firestore.
7. Going live: repeat with `sk_live_...` and a live-mode webhook endpoint.

Writes to `Codes`, `Payments` and `StripeEvents` happen only through these functions (the Firestore rules deny the app).
