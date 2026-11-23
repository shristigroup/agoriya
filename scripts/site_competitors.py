"""The close-fit competitors of TrackFolks: one source for the competitor comparison page and the landing-page price chart.

Table text is taken as is from competitor-analysis.png (India, cheapest annual billing slab, excl. 18% GST).
Chart: yearly cost at the UPPER end of each price range (route features sit on the top plan), rupees at 95 = $1.
"""
import json
import re

RATE = 95  # rupees per dollar, same as the rest of the site
USERS = [10, 20, 30, 50, 100]

# key, label, what it means (shown when the "i" on a chip is clicked)
FEATURES = [
    ("gps", "GPS tracking", "Records where each person is while on duty, using the phone's GPS."),
    ("attendance", "Attendance", "Staff punch in and out from the phone, with the time and place recorded."),
    ("distance", "Distance", "Works out the kilometres each person travelled in a day, for travel claims."),
    ("route", "Route timeline", "Replays the day's path on a map in order, so you see where staff went and when. Only a few apps do this."),
    ("visits", "Visit logging", "Staff record each customer visit with a form, notes or photos."),
    ("geofence", "Geofencing", "Limits punch-in to a set place, or marks attendance automatically when staff enter or leave it."),
    ("face", "Face / selfie attendance", "Checks who is punching in with a selfie or face recognition, to stop buddy punching."),
    ("nosetup", "No setup fee", "No one-time onboarding or per-user setup charge."),
    ("free", "Free tier", "A free plan you can use without paying, usually with a limit on the number of users."),
]

ALL_BASE = {"gps", "attendance"}

# yearly cost in rupees for u users; the upper end of the range
C = [
    dict(key="trackfolks", name="TrackFolks", url="/", tier="Pay as you grow", cost="₹100", setup="₹0",
         feats="GPS, Selfie Attendance, Distance, Route Timeline, Visit Forms, Geofencing coming soon", note="First 10 users free. Capped at $499 a year.",
         has={"gps", "attendance", "distance", "route", "visits", "face", "geofence", "free", "nosetup"}),
    dict(key="connect", name="Connect My World", url="https://www.connectmyworld.in/", tier="One price, all features", cost="₹65 – ₹89", setup="₹0",
         feats="GPS, Attendance, Distance, Route Replay, Geofenced Visits", note="Billed every 3 months in advance. Price falls with team size (₹89 for 6-19 users, ₹79 for 20-49).",
         has={"distance", "route", "visits", "face", "geofence", "nosetup"}, year=lambda u: u * (89 if u < 20 else 79 if u < 50 else 69 if u < 200 else 65) * 12, color="#0891b2"),
    dict(key="unolo", name="Unolo", url="https://unolo.com/", tier="Basic Plan", cost="~₹200 – ₹250", setup="₹0",
         feats="GPS, Attendance, Distance, Visit Forms", note="Starter (~₹100–₹150) lacks TA/conveyance claims.",
         has={"distance", "visits", "geofence", "nosetup"}, year=lambda u: u * 250 * 12, color="#2a78d6"),
    dict(key="daytrack", name="dayTrack", url="https://daytrack.in/", tier="Annual Plan", cost="₹249", setup="₹499 / user",
         feats="GPS, Attendance, Distance, Visit/Beat Logs", note="Min. 2 users; ≤5 users locked into 12-mo upfront.",
         has={"distance", "visits"}, year=lambda u: u * (249 * 12 + 499), color="#c2410c"),
    dict(key="fieldsense", name="FieldSense", url="https://www.fieldsense.in/", tier="Premium Plan", cost="₹250", setup="₹0 (or ₹10k assisted)",
         feats="GPS, Attendance, Distance, Smart Forms", note="Free tier (≤10 users) lacks Smart Forms & phone support.",
         has={"distance", "visits", "geofence", "free", "nosetup"}, year=lambda u: u * 250 * 12, color="#1baf7a"),
    dict(key="breezefsm", name="BreezeFSM", url="https://breezefsm.com/", tier="Base Tracking", cost="Starts at ₹250", setup="Custom",
         feats="GPS, Attendance, Distance, Visit Reporting", note="Geared toward B2B/FMCG sales.",
         has={"distance", "visits", "geofence"}, year=lambda u: u * 250 * 12, color="#7c3aed"),
    dict(key="trackofield", name="TrackoField", url="https://trackobit.com/", tier="Annual Plan", cost="₹475", setup="₹0",
         feats="GPS, Face AI Attendance, Distance, Visits", note="Annual plan, 10-user minimum. ₹570 half-yearly, ₹760 quarterly.",
         has={"distance", "visits", "face", "geofence", "nosetup"}, year=lambda u: u * 475 * 12, color="#0b7285"),
    dict(key="trackwick", name="TrackWick", url="https://trackolap.com/", tier="Plans by feature", cost="₹300 – ₹800", setup="Not published",
         feats="GPS, Attendance, Distance, Leave", note="Price is from a third-party listing (₹300, ₹600 or ₹800 by plan), not the vendor's site.",
         has={"distance"}, year=lambda u: u * 800 * 12, color="#d97706"),
    dict(key="salarybox", name="SalaryBox", url="https://www.salarybox.in/", tier="Starter + CRM Add-on", cost="₹153 – ₹404 (30 users)", setup="₹0",
         feats="GPS, Attendance, Distance, Route Timeline", note="₹1,000 base + ₹20/user + ₹100 live location add-on, plus ₹250 CRM add-on for trips and distance.",
         has={"distance", "route", "geofence", "nosetup"}, year=lambda u: (1000 + u * 370) * 12, color="#6250d6"),
    dict(key="lystloc", name="Lystloc", url="https://www.lystloc.com/", tier="Enterprise Plan", cost="₹349", setup="₹0",
         feats="GPS (360 hrs), Attendance, Distance, Photos", note="Report downloads & APIs cost extra on this tier.",
         has={"distance", "geofence", "nosetup"}, year=lambda u: u * 349 * 12, color="#be185d"),
    dict(key="onthego", name="OnthegO.ai", url="https://onthego.ai/", tier="Custom FFA", cost="₹139 – ₹219", setup="Custom",
         feats="GPS, Attendance, Distance, Visit Forms", note="₹139 (FFA) or ₹219 (FFA+) in India. Distance uses a third-party map API, which adds ₹60.",
         has={"distance", "visits", "geofence"}, year=lambda u: u * 219 * 12, color="#a16207"),
    dict(key="truein", name="Truein", url="https://truein.com/", tier="Time Capture + Tracking", cost="~₹612 (10 users)<br>~₹152 (50 users)", setup="₹0",
         feats="GPS Route History, Face Attendance", note="₹69,000/yr mandatory base fee + ₹450/user/yr.",
         has={"route", "face", "geofence", "nosetup"}, year=lambda u: 69000 + 450 * u, color="#8d6e4a"),
    dict(key="jibble", name="Jibble", url="https://jibble.io/", tier="Ultimate Plan (USD)", cost="$6.99", setup="₹0",
         feats="Live GPS & Route Map, Face Attendance", note="Ultimate plan at the vendor's discounted regional rate; free plan covers unlimited users. No distance (km) or visit forms.",
         has={"route", "face", "geofence", "nosetup"}, year=lambda u: u * 664 * 12, color="#8a8580"),
    dict(key="timeero", name="Timeero", url="https://timeero.com/", tier="Pro + Segmented Add-on", cost="$5 – $10", setup="₹0",
         feats="GPS, Geofenced Attendance, Auto-Mileage", note="Billed in USD. Basic $5 has GPS and mileage; geofencing and the full workday timeline need Pro ($7.50) or Premium ($10).",
         has={"distance", "geofence", "nosetup"}, year=lambda u: u * 950 * 12, color="#7c8f23"),
]
for c in C:
    c["has"] = set(c["has"]) | ALL_BASE


def usd(text):
    """Rupee amounts in the table text, shown in dollars at RATE."""
    def conv(m):
        v = int(m.group(1).replace(",", "")) * (1000 if m.group(2) else 1) / RATE
        return "$0" if v == 0 else "$" + (f"{v:,.0f}" if v >= 10 else f"{v:.2f}")
    return re.sub(r"₹([\d,]+)(k?)", conv, text)


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


# ------------------------------------------------------------------ the competitor comparison section of the landing page
SHOWN = 6  # rows shown before "Show all"; TrackFolks always stays visible

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
.cmp { border-collapse:collapse; width:100%; min-width:860px; font-size:14px; }
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
  var open = false;
  document.getElementById('cmp-toggle').addEventListener('click', function () {
    open = !open; this.textContent = open ? 'Show fewer' : 'Show all ' + rows.length + ' apps'; apply();
  });
  function apply() {
    var on = chips.filter(function (c) { return c.classList.contains('on'); }).map(function (c) { return c.dataset.key; });
    var shown = 0;
    var wrap = document.getElementById('cmp-wrap'), btn = document.getElementById('cmp-toggle');
    if (on.length) { wrap.classList.remove('collapsed'); btn.hidden = true; } else { btn.hidden = false; wrap.classList.toggle('collapsed', !open); }
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


def section_html(esc):
    chips = "".join(
        f'<span class="chip" data-key="{k}" data-label="{esc(label, quote=True)}" data-desc="{esc(desc, quote=True)}">'
        f'<button type="button" class="chip-main" aria-pressed="false">{esc(label)}</button>'
        f'<button type="button" class="chip-i" aria-expanded="false" aria-label="What is {esc(label, quote=True)}?">i</button></span>'
        for k, label, desc in FEATURES)
    rows = ""
    for n, c in enumerate(sorted(C, key=lambda c: c["name"].lower())):  # A to Z, TrackFolks included (highlighted)
        us = c["key"] == "trackfolks"
        name = "TrackFolks" if us else f'<a href="{c["url"]}" target="_blank" rel="noopener nofollow">{esc(c["name"])}</a>'
        cls = " ".join(x for x in ("us" if us else "", "more" if n >= SHOWN and not us else "") if x)
        rows += (f'<tr{f" class={cls!r}".replace(chr(39), chr(34)) if cls else ""} data-has="{" ".join(sorted(c["has"]))}">'
                 f'<td class="prov">{name}</td><td class="price">{usd(c["cost"])}</td><td>{esc(usd(c["setup"]))}</td>'
                 f'<td>{esc(c["feats"])}</td><td>{esc(usd(c["note"]))}</td></tr>\n')
    return f'''<div class="cmp-section reveal" id="competitor-comparison">
<h2 class="section-label">Competitor Comparison</h2>
<p class="cmp-sub">Select features from the chips below to filter the table.</p>
<div class="chips" role="group" aria-label="Filter by feature">{chips}</div>
<div id="chip-info" hidden></div>
<div class="cmp-wrap collapsed" id="cmp-wrap">
<table class="cmp">
<thead><tr><th>Provider</th><th>Monthly Cost / User</th><th>Setup Fee</th><th>Core Field Features Included</th><th>Key Catch / Notes</th></tr></thead>
<tbody>
{rows}</tbody>
</table>
<div id="cmp-empty">No app matches all the selected features.</div>
</div>
<button type="button" class="cmp-toggle" id="cmp-toggle">Show all {len(C)} apps</button>
<script>{PAGE_JS}</script>
</div>'''
