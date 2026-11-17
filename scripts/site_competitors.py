"""The close-fit competitors of TrackFolks: one source for the competitor comparison page and the landing-page price chart.

Table text is taken as is from competitor-analysis.png (India, cheapest annual billing slab, excl. 18% GST).
Chart: yearly cost at the UPPER end of each price range (route features sit on the top plan), rupees at 95 = $1.
"""
import json

RATE = 95  # rupees per dollar, same as the rest of the site
USERS = [10, 20, 30, 50, 100]

# key, label, what it means (shown when the "i" on a chip is clicked)
FEATURES = [
    ("gps", "GPS tracking", "Records where each person is while on duty, using the phone's GPS."),
    ("attendance", "Attendance", "Staff punch in and out from the phone, with the time and place recorded."),
    ("distance", "Distance", "Works out the kilometres each person travelled in a day, for travel claims."),
    ("route", "Route timeline", "Replays the day's path on a map in order, so you see where staff went and when. Only a few apps do this."),
    ("visits", "Visit logging", "Staff record each customer visit with a form, notes or photos."),
    ("face", "Face / selfie attendance", "Checks who is punching in with a selfie or face recognition, to stop buddy punching."),
    ("nosetup", "No setup fee", "No one-time onboarding or per-user setup charge."),
]

ALL_BASE = {"gps", "attendance"}

# yearly cost in rupees for u users; the upper end of the range
C = [
    dict(key="trackfolks", name="TrackFolks", url="/", tier="Pay as you grow", cost="₹100", setup="₹0",
         feats="GPS, Selfie Attendance, Distance, Route Timeline, Visit Forms", note="First 10 users free. Capped at $499 a year.",
         has={"gps", "attendance", "distance", "route", "visits", "face", "nosetup"}),
    dict(key="unolo", name="Unolo", url="https://unolo.com/", tier="Basic Plan", cost="~₹200 – ₹250", setup="₹0",
         feats="GPS, Attendance, Distance, Visit Forms", note="Starter (~₹100–150) lacks TA/conveyance claims.",
         has={"distance", "visits", "nosetup"}, year=lambda u: u * 250 * 12, color="#2a78d6"),
    dict(key="daytrack", name="dayTrack", url="https://daytrack.in/", tier="Annual Plan", cost="₹249", setup="₹499 / user",
         feats="GPS, Attendance, Distance, Visit/Beat Logs", note="Min. 2 users; ≤5 users locked into 12-mo upfront.",
         has={"distance", "visits"}, year=lambda u: u * (249 * 12 + 499), color="#c2410c"),
    dict(key="fieldsense", name="FieldSense", url="https://www.fieldsense.in/", tier="Premium Plan", cost="₹250", setup="₹0 (or ₹10k assisted)",
         feats="GPS, Attendance, Distance, Smart Forms", note="Free tier (≤10 users) lacks Smart Forms & phone support.",
         has={"distance", "visits", "nosetup"}, year=lambda u: u * 250 * 12, color="#1baf7a"),
    dict(key="breezefsm", name="BreezeFSM", url="https://breezefsm.com/", tier="Base Tracking", cost="Starts at ₹250", setup="Custom",
         feats="GPS, Attendance, Distance, Visit Reporting", note="Geared toward B2B/FMCG sales.",
         has={"distance", "visits"}, year=lambda u: u * 250 * 12, color="#7c3aed"),
    dict(key="trackobit", name="TrackoBit", url="https://trackobit.com/", tier="TrackoField Annual", cost="₹300", setup="₹0",
         feats="GPS, Face AI Attendance, Distance, Visits", note="Strict minimum seat thresholds (10 users on annual).",
         has={"distance", "visits", "face", "nosetup"}, year=lambda u: u * 300 * 12, color="#0b7285"),
    dict(key="salarybox", name="SalaryBox", url="https://www.salarybox.in/", tier="Starter + CRM Add-on", cost="₹290 – ₹370", setup="₹0",
         feats="GPS, Attendance, Distance, Route Timeline", note="₹1,000 base + ₹20/user + ₹250 CRM add-on for distance.",
         has={"distance", "route", "nosetup"}, year=lambda u: u * 370 * 12, color="#6250d6"),
    dict(key="lystloc", name="Lystloc", url="https://www.lystloc.com/", tier="Enterprise Plan", cost="₹349", setup="₹0",
         feats="GPS (360 hrs), Attendance, Distance, Photos", note="Report downloads & APIs cost extra on this tier.",
         has={"distance", "nosetup"}, year=lambda u: u * 349 * 12, color="#be185d"),
    dict(key="onthego", name="OnthegO.ai", url="https://onthego.ai/", tier="Custom FFA", cost="~₹250 – ₹450", setup="Custom",
         feats="GPS, Attendance, Distance, Visit Forms", note="Bespoke enterprise workflow setup; no public retail card.",
         has={"distance", "visits"}, year=lambda u: u * 450 * 12, color="#a16207"),
    dict(key="truein", name="Truein", url="https://truein.com/", tier="Time Capture + Tracking", cost="~₹612 (10 users)<br>~₹152 (50 users)", setup="₹0",
         feats="GPS Route History, Face Attendance", note="₹69,000/yr mandatory base fee + ₹450/user/yr.",
         has={"route", "face", "nosetup"}, year=lambda u: 69000 + 450 * u, color="#8d6e4a"),
    dict(key="pagarbook", name="PagarBook Geo", url="https://pagarbook.com/", tier="Geo Basic + Base Plan", cost="~₹558", setup="₹0",
         feats="GPS, Attendance, Distance, Route Timeline", note="₹5,999/yr Geo add-on + ₹699/yr base plan.",
         has={"distance", "route", "nosetup"}, year=lambda u: u * 558 * 12, color="#e87ba4"),
    dict(key="jibble", name="Jibble", url="https://jibble.io/", tier="Ultimate Plan (USD)", cost="~₹680 – ₹690<br>($7.99)", setup="₹0",
         feats="Live GPS & Route Map, Face Attendance", note="Does not calculate total distance (km); no visit forms.",
         has={"route", "face", "nosetup"}, year=lambda u: u * 690 * 12, color="#8a8580"),
    dict(key="timeero", name="Timeero", url="https://timeero.com/", tier="Pro + Segmented Add-on", cost="~₹1,060 ($12.50)", setup="₹0",
         feats="GPS, Geofenced Attendance, Auto-Mileage", note="Billed in USD; Basic ($5) lacks geofencing & visit logs.",
         has={"distance", "nosetup"}, year=lambda u: u * 1060 * 12, color="#7c8f23"),
]
for c in C:
    c["has"] = set(c["has"]) | ALL_BASE


def cost_series():
    s = [dict(key="trackfolks", name="TrackFolks", color="#8B1A1A", dash="", w=3.5, v=[0, 126, 252, 499, 499]),
         dict(key="trackfolks", name="TrackFolks, first year", color="#8B1A1A", dash="6 4", w=2.5, v=[0, 126, 249, 249, 249])]
    for c in C[1:]:
        s.append(dict(key=c["key"], name=c["name"], color=c["color"], dash="", w=2, v=[int(round(c["year"](u) / RATE)) for u in USERS]))
    return s


def chart_block():
    data = json.dumps(dict(users=USERS, ymax=15000, ymin=50, scale="log", ticks=[100, 200, 500, 1000, 2000, 5000, 10000], series=cost_series()))
    return ('<div id="cost-chart" data-highlight=""></div>\n'
            f'<script type="application/json" id="cost-data">{data}</script>\n'
            '<script src="/assets/js/cost-chart.js" defer></script>')


# ------------------------------------------------------------------ the competitor comparison page
PAGE_CSS_EXTRA = """
.cmp-sub { color:var(--muted); font-size:14px; margin-bottom:18px; max-width:none; }
.cmp-cta { display:inline-block; background:var(--red); color:#fff; padding:9px 18px; border-radius:10px; text-decoration:none; font-weight:700; font-size:14px; margin-bottom:22px; }
.chips { display:flex; flex-wrap:wrap; gap:8px; margin-bottom:10px; }
.chip { display:inline-flex; align-items:stretch; border:1.5px solid var(--divider); border-radius:999px; background:var(--surface); overflow:hidden; }
.chip.on { border-color:var(--red); background:var(--red-light); }
.chip button { font:inherit; font-size:13px; border:0; background:none; cursor:pointer; color:var(--text); }
.chip .chip-main { padding:7px 6px 7px 14px; font-weight:600; }
.chip.on .chip-main { color:var(--red-dark); }
.chip .chip-i { width:28px; font-size:12px; font-weight:700; font-style:italic; font-family:Georgia,serif; color:var(--muted); }
.chip .chip-i:hover, .chip .chip-i[aria-expanded="true"] { color:var(--red); }
#chip-info { font-size:13px; color:#3a2a2a; background:var(--surface); border:1px solid var(--divider); border-left:4px solid var(--red); border-radius:8px; padding:8px 12px; margin-bottom:14px; max-width:620px; }
.cmp-wrap { overflow-x:auto; border:1px solid #c9cdd3; background:#fff; }
.cmp { border-collapse:collapse; width:100%; min-width:980px; font-size:14px; }
.cmp th, .cmp td { padding:16px 14px; text-align:left; vertical-align:middle; border:1px solid #d3d6db; position:static; background:none; min-width:0; box-shadow:none; }
.cmp thead th { background:#1e2a3b; color:#fff; font-weight:500; text-align:center; position:static; }
.cmp tbody tr:nth-child(even) td { background:#f7f8fa; }
.cmp td.price { color:#0b5f8a; }
.cmp td.prov { font-weight:600; }
.cmp td.prov a { color:var(--text); text-decoration:none; border-bottom:1px dotted var(--muted); }
.cmp td.prov a:hover { color:var(--red); }
.cmp tr.us td { background:var(--red-light) !important; }
.cmp tr.us td.prov { color:var(--red-dark); }
#cmp-empty { display:none; padding:22px; text-align:center; color:var(--muted); font-size:14px; }
"""

PAGE_JS = """
(function () {
  var rows = [].slice.call(document.querySelectorAll('.cmp tbody tr'));
  var chips = [].slice.call(document.querySelectorAll('.chip'));
  var info = document.getElementById('chip-info');
  var empty = document.getElementById('cmp-empty');
  function apply() {
    var on = chips.filter(function (c) { return c.classList.contains('on'); }).map(function (c) { return c.dataset.key; });
    var shown = 0;
    rows.forEach(function (r) {
      var has = r.dataset.has.split(' ');
      var ok = on.every(function (k) { return has.indexOf(k) > -1; });
      r.hidden = !ok;
      if (ok) shown++;
    });
    empty.style.display = shown ? 'none' : 'block';
  }
  chips.forEach(function (c) {
    var main = c.querySelector('.chip-main'), i = c.querySelector('.chip-i');
    main.addEventListener('click', function () {
      var on = c.classList.toggle('on');
      main.setAttribute('aria-pressed', on ? 'true' : 'false');
      apply();
    });
    i.addEventListener('click', function () {
      var open = i.getAttribute('aria-expanded') === 'true';
      chips.forEach(function (x) { x.querySelector('.chip-i').setAttribute('aria-expanded', 'false'); });
      if (open) { info.hidden = true; return; }
      i.setAttribute('aria-expanded', 'true');
      info.textContent = '';
      var b = document.createElement('strong'); b.textContent = c.dataset.label + ': ';
      info.appendChild(b); info.appendChild(document.createTextNode(c.dataset.desc));
      info.hidden = false;
    });
  });
})();
"""


def page_body(esc):
    chips = "".join(
        f'<span class="chip" data-key="{k}" data-label="{esc(label, quote=True)}" data-desc="{esc(desc, quote=True)}">'
        f'<button type="button" class="chip-main" aria-pressed="false">{esc(label)}</button>'
        f'<button type="button" class="chip-i" aria-expanded="false" aria-label="What is {esc(label, quote=True)}?">i</button></span>'
        for k, label, desc in FEATURES)
    rows = ""
    for c in C:
        us = c["key"] == "trackfolks"
        name = "TrackFolks" if us else f'<a href="{c["url"]}" target="_blank" rel="noopener nofollow">{esc(c["name"])}</a>'
        rows += (f'<tr{" class=us" if us else ""} data-has="{" ".join(sorted(c["has"]))}">'
                 f'<td class="prov">{name}</td><td>{esc(c["tier"])}</td><td class="price">{c["cost"]}</td><td>{esc(c["setup"])}</td>'
                 f'<td>{esc(c["feats"])}</td><td>{esc(c["note"])}</td></tr>\n')
    return f'''<h1>Field Force Tracking Software — India Pricing Comparison</h1>
<p class="cmp-sub">Cheapest annual billing slab (excl. 18% GST) | Normalized for GPS, attendance, distance, visit logging &amp; setup</p>
<a class="cmp-cta" href="/#download">Download TrackFolks for free</a>
<div class="chips" role="group" aria-label="Filter by feature">{chips}</div>
<div id="chip-info" hidden></div>
<div class="cmp-wrap">
<table class="cmp">
<thead><tr><th>Provider</th><th>Qualifying Tier</th><th>Monthly Cost / User</th><th>Setup Fee</th><th>Core Field Features Included</th><th>Key Catch / Notes</th></tr></thead>
<tbody>
{rows}</tbody>
</table>
<div id="cmp-empty">No app matches all the selected features.</div>
</div>
<script>{PAGE_JS}</script>'''
