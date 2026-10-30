// Pricing rules for a paid TrackFolks organisation. Keep in step with the pricing section of the website and assets/js/checkout.js.
//   - The first 10 users are free.
//   - Beyond that: $12 per user per year ($1 a month).
//   - The yearly total is capped: $199 in the first year, $399 on every renewal. Renewals are invoiced by hand, not automatic.
const FREE_USERS = 10;
const PER_USER_YEAR_CENTS = 1200;
const CAP_FIRST_YEAR_CENTS = 19900;
const CAP_RENEWAL_CENTS = 39900;
const MAX_USERS = 100; // above this, buyers email for a custom quote and cannot pay online

function planAmountCents(users, firstYear) {
  const paidUsers = Math.max(0, users - FREE_USERS);
  return Math.min(paidUsers * PER_USER_YEAR_CENTS, firstYear ? CAP_FIRST_YEAR_CENTS : CAP_RENEWAL_CENTS);
}

module.exports = { FREE_USERS, MAX_USERS, planAmountCents };
