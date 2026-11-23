"""The comparison articles built on the landing-page competitor set (scripts/site_competitors.py):

  - "Top N field force automation software compared"  (the new top article)
  - "Alternative to X" pages for the competitors that had no page before (dayTrack, BreezeFSM, TrackoField, Lystloc, OnthegO.ai)
  - redirect stubs for the two retired articles (the old compared guide and the old "alternatives to the top 11" hub)

The older "Alternative to X" pages (scripts/site_data.py set) stay as committed files and are linked from here.
Features are the nine on the landing page. Ratings: Google Play and App Store, India storefront.
"""
from site_core import *  # noqa: F401,F403
import site_competitors as comp
import site_guide as guide

CHECKED_NEW = "November 2026"
COMPETITORS = comp.C[1:]
TF_ROW = comp.C[0]
NC = len(COMPETITORS)
TOP_TITLE = "How to Pick a Field Force Automation App"

# (rating, count) per store. None = no listing found or no ratings yet.
# dayTrack, BreezeFSM, Lystloc and TrackoField read from the store pages in November 2026 (TrackoField is TrackoBit's app; its iPhone listing is under
# the publisher name "Pulkit Jain", a TrackoBit director per third-party listings). No Google Play listing for OnthegO.ai could be located.
NEW_RATINGS = {
    "unolo": dict(play=(4.7, 6470), ios=(3.3, 59)),
    "fieldsense": dict(play=(3.9, 10900), ios=(2.5, 130)),
    "daytrack": dict(play=(4.08, 868), ios=(4.23, 22)),
    "breezefsm": dict(play=(4.10, 22), ios=None),
    "trackofield": dict(play=(3.30, 212), ios=(3.33, 15)),
    "trackwick": dict(play=(4.0, 561), ios=None),
    "connect": dict(play=(4.1, 206), ios=None),
    "salarybox": dict(play=(4.3, 11700), ios=(3.7, 391)),
    "lystloc": dict(play=(3.94, 521), ios=(4.03, 35)),
    "onthego": dict(play=(4.3, 518), ios=(3.17, 18)),
    "truein": dict(play=(4.4, 2960), ios=(3.9, 75)),
    "jibble": dict(play=(4.5, 5400), ios=(4.8, 1600)),
    "timeero": dict(play=(3.0, 841), ios=(4.7, 1656)),
}
LABELS = {k: lbl for k, lbl, _ in comp.FEATURES}
DESCS = {k: d for k, _, d in comp.FEATURES}
TF_YEAR = dict(zip(comp.USERS, [0, 126, 252, 499, 499]))  # dollars a year, capped; first 10 users free


def ratings(c):
    r = NEW_RATINGS[c["key"]]
    return r["play"], r["ios"]


def alt_url(c):
    k = c["key"]
    return "/" + (guide.path(k) if k in guide.A else alt_path(P[k]))


def clean(name):
    return name.replace(" Geo", "")


def rating_cell(r):
    if r is None:
        return '<td class="n">Not found</td>'
    return star_cell(*r)


def count(c):
    return sum(r[1] for r in ratings(c) if r)


def cost_text(c):
    return comp.usd(c["cost"]).replace("<br>", ", ")


def jsonld(headline, path):
    return {"@context": "https://schema.org", "@type": "Article", "headline": headline,
            "dateModified": "2026-11-17", "author": {"@type": "Organization", "name": "TrackFolks"},
            "publisher": {"@type": "Organization", "name": "TrackFolks", "url": SITE + "/"},
            "mainEntityOfPage": f"{SITE}/{path}"}


# ------------------------------------------------------------------ essential and good-to-have features, and the score
# Source: each vendor's public site (November 2026), plus the October 2026 research in site_data.py for the seven older providers.
# "Listed" only where a page says so; absence means "not listed", not "certainly missing".
# Timeero's messaging is chat, not customizable forms, so it is not counted for forms.
GOOD_HAS = {
    "trackfolks": {"expense"},
    "unolo": {"order", "expense", "leave"},
    "daytrack": {"order"},
    "fieldsense": {"leave", "expense", "forms", "biometric"},
    "breezefsm": {"order", "expense", "task"},
    "trackofield": {"roster", "order", "payroll", "leave", "expense", "task", "forms"},
    "salarybox": {"roster", "payroll", "leave", "expense", "biometric"},
    "lystloc": {"payroll", "leave", "expense", "task", "forms"},
    "onthego": {"order", "leave", "expense", "forms"},
    "truein": {"roster", "payroll", "leave", "biometric"},
    "jibble": {"roster", "payroll", "leave", "biometric"},
    "timeero": {"roster", "payroll", "leave", "expense"},
    "trackwick": {"leave"},
    "connect": {"task", "forms"},
}


# Partly met: the app has no payroll module but exports the data to Excel, so payroll can be done by hand. (TrackFolks; OnthegO.ai's site lists Excel reports.)
PARTIAL = {("trackfolks", "payroll"): "Excel export", ("onthego", "payroll"): "Excel export"}

# key, label, group (E essential, G good to have, C commercial), the underlying landing / research keys (any one is enough)
COLS = [
    ("attendance", "Attendance", "E", ("attendance",)),
    ("face", "Face / selfie attendance", "E", ("face",)),
    ("live", "Live location", "E", ("gps",)),
    ("distance", "Distance", "E", ("distance",)),
    ("route", "Route timeline", "E", ("route",)),
    ("tom", "Task, order & visit management", "E", ("visits", "order", "task")),  # visit logging alone is the cheaper alternative
    ("expense", "Expense logging", "E", ("expense",)),
    ("roster", "Roster, shift & leave management", "E", ("roster", "leave")),
    ("geofence", "Geofencing", "G", ("geofence",)),
    ("forms", "Customizable forms", "G", ("forms",)),
    ("payroll", "Payroll processing", "G", ("payroll",)),
    ("biometric", "Biometric / QR / kiosk attendance", "G", ("biometric",)),
    ("nosetup", "No setup fee", "C", ("nosetup",)),
    ("free", "Free tier", "C", ("free",)),
]
GROUP = {k: g for k, _, g, _ in COLS}
FEAT_LABEL = {k: l for k, l, _, _ in COLS}
SRC = {k: src for k, _, _, src in COLS}
ALL_KEYS = [k for k, _, _, _ in COLS]
ESSENTIAL = [k for k in ALL_KEYS if GROUP[k] == "E"]
GOOD_KEYS = [k for k in ALL_KEYS if GROUP[k] == "G"]
NESS, NGOODN = len(ESSENTIAL), len(GOOD_KEYS)


def has(c, k):
    return any(x in c["has"] or x in GOOD_HAS[c["key"]] for x in SRC[k])


def partial(c, k):
    return (c["key"], k) in PARTIAL and not has(c, k)


def pts_for(c, k):
    return 5 if has(c, k) else 3 if partial(c, k) else 1


def nfeat(c):
    """Essential plus good-to-have features listed."""
    return sum(1 for k in ESSENTIAL + GOOD_KEYS if has(c, k))


def ness(c):
    return sum(1 for k in ESSENTIAL if has(c, k))


SETUP_PER_USER = {"daytrack": 499}  # rupees per user, from the landing-page table


def per_user_month(c):
    """Dollars per user per month for a 30-user team, at the top of the price range."""
    if c["key"] == "trackfolks":
        return TF_YEAR[30] / 30 / 12
    setup = SETUP_PER_USER.get(c["key"], 0)  # one-time fee: already scored under "No setup fee", so not counted in the price colour
    return (c["year"](30) - 30 * setup) / comp.RATE / 30 / 12


WEIGHT = {k: (2 if GROUP[k] == "E" else 1) for k in ALL_KEYS}  # essential features count double
MAX_PTS = sum(5 * w for w in WEIGHT.values()) + 3 * 5


def score(c):
    """Out of 100. Each feature scores 5 if listed, 1 if not, times its weight (2 essential, 1 good-to-have and commercial);
    price and the two store ratings score 5 / 3 / 1 with weight 1."""
    pts = sum(WEIGHT[k] * pts_for(c, k) for k in ALL_KEYS)
    pts += SCORE_POINTS[price_class(per_user_month(c))]
    for r in (ratings(c) if c["key"] != "trackfolks" else (None, None)):
        pts += SCORE_POINTS[star_class(r[0])] if r else 1
    return round(pts * 100 / MAX_PTS), 100


def avg_rating(c):
    rs = [r for r in ratings(c) if r] if c["key"] != "trackfolks" else []
    n = sum(r[1] for r in rs)
    return (sum(r[0] * r[1] for r in rs) / n, n) if n else (0, 0)


def picks():
    pool = [TF_ROW] + COMPETITORS
    out = ""

    def block(title, rows):
        nonlocal out
        out += f"<h3>{esc(title)}</h3>\n<ol class=\"ranked\">\n" + "".join(
            f'<li><strong><a href="{"/" if c is TF_ROW else c["url"]}"{"" if c is TF_ROW else ' rel="noopener"'}>{esc(clean(c["name"]))}</a></strong>: {esc(a)}. <span class="muted">{esc(b)}</span></li>\n' for c, a, b in rows[:3]) + "</ol>\n"
    sc = sorted(pool, key=lambda c: (-score(c)[0], clean(c["name"])))
    block("Best overall (highest score in the table)", [(c, f"score {score(c)[0]} out of {score(c)[1]}", f"{ness(c)} of {NESS} essential features") for c in sc])
    rb = sorted([c for c in COMPETITORS if avg_rating(c)[1] >= 500], key=lambda c: -avg_rating(c)[0])
    block("Most robust (best store ratings, among apps with 500 or more ratings)",
          [(c, f"{avg_rating(c)[0]:.2f} stars from {avg_rating(c)[1]:,} ratings", "Google Play and App Store combined") for c in rb])
    fr = sorted(pool, key=lambda c: (-nfeat(c), clean(c["name"])))
    block(f"Most feature rich (most of the {NESS + NGOODN} essential and good-to-have features)",
          [(c, f"{nfeat(c)} of {NESS + NGOODN} features", f"{ness(c)} essential, {nfeat(c) - ness(c)} good-to-have") for c in fr])
    vm = sorted(pool, key=lambda c: -ness(c) / per_user_month(c))
    block("Most value for money (essential features per dollar of price per user per month; only essential features are counted)",
          [(c, f"{ness(c)} of {NESS} essential features at about ${per_user_month(c):.2f} per user per month", f"{ness(c) / per_user_month(c):.1f} essential features per dollar") for c in vm])
    return out


# ------------------------------------------------------------------ the top article
ESSENTIAL_TEXT = [
    ("Attendance", "Staff punch in and out from the phone, with the time and place recorded."),
    ("Face / selfie attendance", "Checks who is punching in with a selfie or face recognition, to stop buddy punching."),
    ("Live location", "Records where each person is while on duty, using the phone's GPS, so supervisors can see where staff are right now."),
    ("Distance", "Works out the kilometres each person travelled in a day, for travel claims."),
    ("Route timeline", "Replays the day's path on a map in order, so you see where staff went and when. Only a few apps do this."),
    ("Task, order & visit management", "Assign tasks, take customer orders or record customer visits from the phone. Full task and order management is the most complete option. Visit logging, with a form, notes or photos, is a cheaper alternative that covers most teams."),
    ("Expense logging", "Staff log travel and other expenses with bills from the phone, and managers approve them, instead of collecting paper bills."),
    ("Roster, shift & leave management", "Plan who works which shift and track leave. A roster also lets the app send a notification to both the employee and the supervisor when attendance is not marked on time, so gaps are caught the same day."),
    ("Export to Excel", "All attendance, distance and visit data can be downloaded as a spreadsheet. This makes payroll do-it-yourself: you run salary from clean data in your own tool or sheet, without paying for a built-in payroll module."),
    ("Real-time notifications", "Supervisors are told when someone punches in, punches out or logs a visit, so they act on the day instead of reading a report later."),
]
GOOD = [
    ("Geofencing", "Limits punch-in to a set place, or marks attendance automatically when staff enter or leave it. A selfie check-in together with the recorded location can pretty much compensate for it, so it is rarely worth paying more for."),
    ("Customizable forms", "Build your own forms for audits, checklists or reports. Useful when a standard visit form does not fit what your client asks for."),
    ("Payroll processing", "The app calculates salary from attendance, leave and deductions. Because export to Excel is essential and already makes payroll doable on your own, built-in payroll is good to have, not a must."),
    ("Biometric, QR or kiosk attendance", "Needs devices installed at each site, which is expensive, and works only at fixed places. Mobile attendance is much easier and more efficient for field staff."),
]


def build_top():
    ranked = sorted(COMPETITORS, key=count, reverse=True)  # used for the list of pages below
    pool = sorted([TF_ROW] + COMPETITORS, key=lambda c: clean(c["name"]).lower())
    feat_head = "".join(f'<th>{esc(FEAT_LABEL[k])}</th>' for k in ALL_KEYS)
    head = f"<th>Provider and score</th><th>Android (Google Play)</th><th>iPhone (App Store)</th><th>Price per user per month</th>{feat_head}"
    rows = ""
    for c in pool:
        tf = c is TF_ROW
        if tf:
            rt = '<td class="n">New listing</td><td class="n">New listing</td>'
            name, price = "TrackFolks", "$1.05 (first 10 users free, capped at $499 a year)"
        else:
            pl, io = ratings(c)
            rt = rating_cell(pl) + rating_cell(io)
            name = f'<a href="{alt_url(c)}">{esc(clean(c["name"]))}</a>'
            price = esc(cost_text(c))
        cells = "".join(f'<td class="o">{esc(PARTIAL[(c["key"], k)])}</td>' if partial(c, k)
                        else f'<td class="{"g" if has(c, k) else "r"}">{"✓" if has(c, k) else "–"}</td>' for k in ALL_KEYS)
        sc, top = score(c)
        rows += f'<tr{" class=tf" if tf else ""}><th scope="row">{name}<span class="score">Score {sc} / {top}</span></th>{rt}<td class="{price_class(per_user_month(c))}">{price}</td>{cells}</tr>\n'
    must = "".join(f'<div class="factor"><h3><span class="num">{i}</span>{esc(t)}</h3><p>{esc(d)}</p></div>' for i, (t, d) in enumerate(ESSENTIAL_TEXT, 1))
    good = "".join(f"<li><strong>{esc(t)}:</strong> {esc(d)}</li>" for t, d in GOOD)
    price_feats = "".join(f"<li><strong>{esc(LABELS[k])}:</strong> {esc(DESCS[k])}</li>" for k in ("nosetup", "free"))
    body = f'''    <h1>{esc(TOP_TITLE)}</h1>
    <p class="meta">Last checked {CHECKED_NEW} · What a field force automation app should do, which features are optional, and {NC} apps to look at</p>
    <img class="hero-img" src="/assets/images/field-force-automation-software-comparison.png" width="1376" height="768" alt="Illustration of field force automation software: a field worker with a tablet and phone, a route map, and a supervisor watching a dashboard, linked by tracking, scheduling, efficiency and productivity" />
    <h2>Who needs field force automation software</h2>
    <p>Any business with people who work away from a desk can use it. It matters most to manpower and staffing companies, typically blue collar workforce providers, that supply field staff to pharma, FMCG, BFSI and logistics companies. These companies cannot see their people at work, yet their clients expect proof that the staff turned up and did the job.</p>
    <p>Most of them manage this on WhatsApp today. Each team has a group. Staff post a photo and an update from the field and tag their supervisor. It is quick to start and everyone already has the app, but the data is scattered across chats. Nobody can say how many people were present last Tuesday without scrolling, and nothing is ready for payroll.</p>
    <h2>What changes with a field force automation app</h2>
    <ul>
      <li><strong>One place for all data.</strong> The owner has attendance, locations, distance travelled and customer visits in one place, instead of in many chat groups.</li>
      <li><strong>Easy payroll.</strong> Export the data to Excel when you need it, and run payroll from clean attendance records.</li>
      <li><strong>Real-time supervision.</strong> Supervisors see updates as they happen and get notifications, instead of waiting for someone to post in a group.</li>
    </ul>
    <h2>Essential features</h2>
    <p>These are the features to expect from any app you shortlist. If an app lacks one, ask why.</p>
    <div class="factors">{must}</div>
    <h2>Good-to-have features</h2>
    <p>Many apps add these, and they are often what makes a plan cost more. Take them only if your business needs them today, because you pay for them whether or not your team uses them.</p>
    <ul>{good}</ul>
    <h2>Check the price carefully</h2>
    <p>Prices are quoted per user per month, but the real cost depends on the fine print: the plan that includes route and distance, a minimum number of users, a base fee, a setup fee or an add-on for each feature. Work out the yearly cost for your own headcount before you decide.</p>
    <ul>{price_feats}</ul>
    <h2>How to choose</h2>
    <ol>
      <li>List the essential features above and the good-to-haves you really need.</li>
      <li>Shortlist two or three apps that list those features publicly.</li>
      <li>Work out the yearly cost for your number of users, with base and setup fees included.</li>
      <li>Look at the app store ratings and how many people rated it. A high score from a handful of ratings means little.</li>
      <li>Try it with one team on the phones your staff actually use before you roll it out to everyone.</li>
    </ol>
    <h2>{NC} apps compared</h2>
    <div class="scroll" style="max-height:none"><table style="min-width:2300px"><thead><tr>{head}</tr></thead><tbody>
{rows}</tbody></table></div>
    <p class="legend"><strong>How the score works (out of 100)</strong></p>
    <ul class="legend">
      <li><strong>Features:</strong> 5 points if listed, 3 if partly met (amber), 1 if not. The {NESS} essential features count double; the {NGOODN} good-to-have features and the two price terms (no setup fee, free tier) count once.</li>
      <li><strong>Price:</strong> per user per month for a 30-user team. Green below $2, amber $2 to $3, red above $3. Counts once.</li>
      <li><strong>Ratings:</strong> each store rating counts once. Green 4.5 and above, amber 4.0 and above, red below, grey (1 point) if there is no listing.</li>
      <li><strong>Ticks:</strong> ✓ means listed publicly. A dash means we could not find it, not that it is certainly missing.</li>
      <li><strong>Merged features:</strong> visit logging alone counts for "Task, order & visit management". A roster or leave management counts for "Roster, shift & leave management".</li>
      <li><strong>Payroll:</strong> amber "Excel export" means no payroll module but data export to Excel (TrackFolks and OnthegO.ai; not checked for every vendor).</li>
      <li><strong>Not in the table:</strong> real-time notifications are essential, but most vendors do not state them.</li>
      <li><strong>Prices:</strong> annual plan, dollars at ₹95 = $1, excluding 18% GST, coloured by the top of each vendor's range. Ratings show stars and the number of ratings.</li>
    </ul>
    <h2>Best app by category</h2>
    {picks()}
    <p>Each app has its own page with a side-by-side look at what it includes and the other apps closest to it:</p>
    <ul>{"".join(f'<li><a href="{alt_url(c)}">Alternative to {esc(clean(c["name"]))}</a></li>' for c in ranked)}</ul>
{disclosure()}'''
    desc = ("Who needs field force automation software, the essential and good-to-have features, how to compare prices, "
            f"and {NC} apps compared on ratings, price and features.")
    w(TOP_PATH, page(f"{TOP_TITLE} (2026)", desc, TOP_PATH, body, jsonld(TOP_TITLE, TOP_PATH)))


# ------------------------------------------------------------------ retired articles
def stub(path, title):
    w(path, f'''<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{esc(title)}</title>
<link rel="canonical" href="{SITE}/{TOP_PATH}" />
<meta http-equiv="refresh" content="0; url=/{TOP_PATH}" />
<meta name="robots" content="noindex, follow" /></head>
<body><p>This guide has moved: <a href="/{TOP_PATH}">{esc(TOP_TITLE)}</a>.</p></body></html>
''')


def build_all():
    build_top()
    stub(COMPARE_PATH, "Comparing the Top 11 Field Force Tracking Apps")
    stub(HUB_PATH, "Alternatives to the Top 11 Attendance and Field Force Tracking Apps")
