// Pay for more users: asks the createCheckoutSession function for a quote, then sends the buyer to Stripe Checkout.
// The server decides the price (assets here only display it). Rules: first 10 users free, then $12 per user per year,
// capped at $199 in the first year and $399 on renewal. Renewals are invoiced by hand, not automatic.
(function () {
  var root = document.getElementById('pay-box');
  if (!root) return;
  var API = 'https://asia-south1-agoriya-app.cloudfunctions.net/createCheckoutSession';
  var codeEl = root.querySelector('[name=code]'), usersEl = root.querySelector('[name=users]');
  var quoteEl = root.querySelector('.pay-quote'), btn = root.querySelector('button[type=submit]'), form = root.querySelector('form');
  var timer = null, ok = false;

  function usd(cents) { return '$' + (cents / 100).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 }); }
  function post(body) {
    return fetch(API, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, body: j }; }); });
  }
  function say(text, bad) { quoteEl.textContent = text; quoteEl.className = 'pay-quote' + (bad ? ' bad' : ''); }

  function refresh() {
    clearTimeout(timer);
    ok = false; btn.disabled = true;
    var code = codeEl.value.trim().toUpperCase(), users = parseInt(usersEl.value, 10);
    if (code.length !== 6 || !(users > 10)) { say(code.length === 6 && users <= 10 ? 'The first 10 users are free. Enter a team size above 10.' : 'Enter your organisation code and team size to see the price.', false); return; }
    say('Checking…', false);
    timer = setTimeout(function () {
      post({ code: code, users: users, dryRun: true }).then(function (r) {
        if (!r.ok) { say(r.body.error || 'Something went wrong. Please try again.', true); return; }
        var q = r.body;
        say('Organisation ' + q.code + ' (now ' + q.currentLimit + ' users). ' + usd(q.amountCents) + ' for ' + q.users + ' users for one year' +
            (q.firstYear ? ' (first-year price, capped at $199)' : ' (renewal price, capped at $399)') +
            (q.testMode ? '. Test mode: no real charge.' : '.'), false);
        ok = true; btn.disabled = false;
      }).catch(function () { say('Could not reach the server. Please try again.', true); });
    }, 350);
  }
  codeEl.addEventListener('input', function () { codeEl.value = codeEl.value.toUpperCase(); refresh(); });
  usersEl.addEventListener('input', refresh);
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (!ok) return;
    btn.disabled = true; btn.textContent = 'Opening Stripe…';
    post({ code: codeEl.value.trim().toUpperCase(), users: parseInt(usersEl.value, 10) }).then(function (r) {
      if (r.ok && r.body.url) { window.location.href = r.body.url; return; }
      say(r.body.error || 'Something went wrong. Please try again.', true);
      btn.textContent = 'Pay with Stripe'; btn.disabled = false;
    }).catch(function () { say('Could not reach the server. Please try again.', true); btn.textContent = 'Pay with Stripe'; btn.disabled = false; });
  });
  refresh();
})();
