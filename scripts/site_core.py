"""Shared building blocks for the generated pages: formatting, the pricing chart block, the comparison matrix,
the page shell, and the rule that picks alternatives. Data lives in site_data.py."""
import html
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from site_data import *  # noqa: E402,F401,F403
from site_css import PAGE_CSS  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
esc = html.escape
CODE_CLASS = {"y": "g", "p": "o", "x": "r", "n": "n"}
ALL = sorted(P.values(), key=lambda p: p["name"].lower())
BY_RANK = sorted(P.values(), key=lambda p: p["rank"])
N = len(P)
COMPARE_SLUG = "field-force-tracking-apps-compared"
HUB_SLUG = "alternatives-to-top-field-force-tracking-apps"
COMPARE_PATH = f"comparison/{COMPARE_SLUG}.html"
HUB_PATH = f"comparison/{HUB_SLUG}.html"
RETIRED = [f"comparison/{TOP10_SLUG}.html", "comparison/alternative-to-beatroute-field-force-tracking-app.html",
           "comparison/alternative-to-fieldassist-field-force-tracking-app.html"]


def w(path, text):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as f:
        f.write(text)


def cap(t):
    return t[0].upper() + t[1:]


def lc1(t):
    return t[0].lower() + t[1:]


def money(v):
    return f"${v:,.2f}"


def per_user(p):
    if p.get("y1") is None:
        return "Not published"
    if abs(p["y1"] - p["renew"]) < 0.005:
        return money(p["y1"]) + p["mark"]
    return f'{money(p["y1"])} year 1, {money(p["renew"])} after renewal{p["mark"]}'


def alt_path(p):
    return f"comparison/alternative-to-{p['slug']}-field-force-tracking-app.html"


# ------------------------------------------------------------------ pricing data and chart
def cost_series():
    n = USERS
    r = lambda v: int(round(v))
    return [
        dict(key="trackfolks", name="TrackFolks", color="#8B1A1A", dash="", w=3.5, v=[0, 120, 240, 399, 399]),
        dict(key="trackfolks", name="TrackFolks, first year", color="#8B1A1A", dash="6 4", w=2.5, v=[0, 120, 199, 199, 199]),
        dict(key="connecteam", name="Connecteam", color="#2a78d6", dash="", w=2, v=[0, 348, 348, 540, 1020]),
        dict(key="salarybox", name="SalaryBox", color="#6250d6", dash="", w=2, v=[r(u * 175 / 95 * 12) for u in n]),
        dict(key="truein", name="Truein", color="#8d6e4a", dash="", w=2, v=[r((69000 + 450 * u) / 95) for u in n]),
        dict(key="fieldsense", name="FieldSense, first year*", color="#1baf7a", dash="6 4", w=2, v=[r(u * 1000 / 95) for u in n]),
        dict(key="fieldsense", name="FieldSense, after renewal*", color="#1baf7a", dash="", w=2, v=[r(u * 3000 / 95) for u in n]),
        dict(key="quickbooks", name="QuickBooks Time", color="#eb6834", dash="", w=2, v=[(20 + 10 * u) * 12 for u in n]),
        dict(key="clockify", name="Clockify", color="#8a8580", dash="", w=2, v=[r(u * 7.99 * 12) for u in n]),
        dict(key="jibble", name="Jibble✱", color="#e87ba4", dash="", w=2, v=[r(u * 7.99 * 12) for u in n]),
        dict(key="hubstaff", name="Hubstaff✱", color="#0b7285", dash="", w=2, v=[r(u * 120) for u in n]),
        dict(key="timeero", name="Timeero", color="#7c8f23", dash="", w=2, v=[r(u * 60) for u in n]),
    ]


PRICE_NOTE = ("* FieldSense: per-user price worked out from what a FieldSense customer told us: Rs 25,000 for 25 users in the first year, rising to Rs 75,000 after renewal; "
              "the price at other team sizes assumes the same per-user rate. ✱ Jibble: the vendor's pages did not list a full price table, so the figure is from third-party sources that disagree. "
              "✱ Hubstaff: the Team plan at $10 per user, without the Locations add-on that GPS tracking needs, whose price we could not find. "
              "QuickBooks Time is the Premium plan ($20 a month base fee + $10 per user). Clockify is the Pro plan. SalaryBox is Rs 75 per user plus Rs 100 for live location. "
              "Truein is the Time Capture plan (Rs 250 per user per year + a Rs 69,000 a year base fee) plus the Rs 200 per user live tracking add-on. Timeero is the Basic plan.")


def render_partial(name, **values):
    """Fill a template from scripts/partials/. The same partial is included in the landing page, the comparison guide and every alternative page."""
    with open(os.path.join(os.path.dirname(__file__), "partials", name)) as f:
        return f.read().format(**values).rstrip("\n")


def pricing_block(highlight=""):
    """The price chart and its table of numbers (partial: scripts/partials/pricing_chart.html)."""
    S = cost_series()
    data = json.dumps(dict(users=USERS, ymax=15000, ymin=50, scale="log", ticks=[100, 200, 500, 1000, 2000, 5000, 10000], series=S))
    names = []
    for s in S:
        if s["name"] not in names:
            names.append(s["name"])
    head = "".join(f"<th>{esc(nm)}</th>" for nm in names)
    rows = ""
    for i, u in enumerate(USERS):
        cells = "".join(
            f'<td class="{"us" if nm.startswith("TrackFolks") else ""}">${next(s for s in S if s["name"] == nm)["v"][i]:,}</td>' for nm in names)
        rows += f"<tr><td>{u}</td>{cells}</tr>\n"
    unp = [p["name"] for p in ALL if p["y1"] is None]
    return render_partial("pricing_chart.html", highlight=highlight, data=data, checked=CHECKED, head=head, rows=rows, note=PRICE_NOTE,
                          unpriced=esc(" and ".join(unp)), unpriced_verb="they are" if len(unp) > 1 else "it is")


# ------------------------------------------------------------------ matrix and category lists
def fcell(code, text):
    return f'<td class="{CODE_CLASS[code]}">{esc(text)}</td>'


def star_cell(score, count):
    cls = "g" if score >= 4.5 else "o" if score >= 4.0 else "r"
    return f'<td class="{cls}">{score:.1f} ★ ({count:,})</td>'


def matrix():
    head = "<th>Provider</th>" + "".join(f"<th>{esc(label)}</th>" for _, label in FEATURES)
    head += "<th>Price per user per month, year 1</th><th>Price per user per month, after renewal</th><th>Main features</th><th>Android rating (Google Play)</th><th>iPhone rating (App Store)</th>"
    rows = ""
    for p in sorted(list(P.values()) + [TF], key=lambda x: x["name"].lower()):
        cells = "".join(fcell(*p["f"][k]) for k, _ in FEATURES)
        if p["key"] == "trackfolks":
            y1, rn, pc1, pc2 = f"{money(p['y1'])} (free for 10 users)", money(p["renew"]), "g", "g"
            rt = '<td class="n">New listing</td><td class="n">New listing</td>'
        else:
            if p["y1"] is None:
                y1 = rn = "Not published"
                pc1 = pc2 = "n"
            else:
                y1, rn = money(p["y1"]) + p["mark"], money(p["renew"]) + p["mark"]
                pc1 = "g" if p["y1"] <= 2 else "o" if p["y1"] <= 8 else "r"
                pc2 = "g" if p["renew"] <= 2 else "o" if p["renew"] <= 8 else "r"
            rt = star_cell(*p["play"][:2]) + star_cell(*p["ios"][:2])
        rows += (f'<tr{" class=tf" if p["key"] == "trackfolks" else ""}><th scope="row">{esc(p["name"])}</th>{cells}'
                 f'<td class="{pc1}">{esc(y1)}</td><td class="{pc2}">{esc(rn)}</td><td class="n">{esc(", ".join(p["key_features"]))}</td>{rt}</tr>\n')
    return f'<div class="scroll"><table><thead><tr>{head}</tr></thead><tbody>\n{rows}</tbody></table></div>'


MAX_PER_CATEGORY = 5


def _link(p, label):
    href = "/#download" if p["key"] == "trackfolks" else p["url"]
    return f'<a href="{href}" rel="noopener">{esc(label)}</a>'


def _items(rows):
    out = ""
    for i, (p, extra, note) in enumerate(rows[:MAX_PER_CATEGORY]):
        nm = "TrackFolks" if p["key"] == "trackfolks" else p["name"]
        shown = _link(p, nm) if i == 0 else esc(nm)
        out += f'<li><strong>{shown}</strong>: {esc(extra)}. <span class="muted">{esc(note)}</span></li>\n'
    return out


def top_by_price():
    out = ""
    pool = list(P.values()) + [TF]
    pop = sorted(P.values(), key=lambda p: -(p["play"][1] + p["ios"][1]))
    out += "<h3>Most popular (most ratings on both stores combined)</h3>\n<ol class=\"ranked\">\n" + _items([
        (p, f'{p["play"][1] + p["ios"][1]:,} ratings', f'{p["play"][1]:,} on Google Play, {p["ios"][1]:,} on the App Store') for p in pop]) + "</ol>\n"
    liked = sorted(P.values(), key=lambda p: -((p["play"][0] + p["ios"][0]) / 2))
    out += "<h3>Most liked (average of the Google Play and App Store ratings)</h3>\n<ol class=\"ranked\">\n" + _items([
        (p, f'{(p["play"][0] + p["ios"][0]) / 2:.2f} stars on average', f'{p["play"][0]:.1f} on Google Play, {p["ios"][0]:.1f} on the App Store ({p["ios"][1]:,} App Store ratings)') for p in liked]) + "</ol>\n"
    for key, label in FEATURES:
        if key == "free":
            continue
        have = [p for p in pool if p["f"][key][0] in ("y", "p")]
        have.sort(key=lambda p: (p["y1"] is None, p["y1"] if p["y1"] is not None else 0, p["name"]))
        rows = [(p, "price not published" if p["y1"] is None else per_user(p) + " per user per month", p["f"][key][1]) for p in have]
        out += f"<h3>{esc(label)}, cheapest first</h3>\n<ol class=\"ranked\">\n{_items(rows)}</ol>\n"
    return out


# ------------------------------------------------------------------ page shell
def page(title, desc, slug_path, body, jsonld=None):
    url = f"{SITE}/{slug_path}"
    og = f"{SITE}/assets/images/og.png"
    ld = f'<script type="application/ld+json">\n{json.dumps(jsonld, indent=2, ensure_ascii=False)}\n</script>' if jsonld else ""
    return f'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>{esc(title)}</title>
  <meta name="description" content="{esc(desc, quote=True)}" />
  <meta name="robots" content="index, follow, max-image-preview:large" />
  <meta name="theme-color" content="#8B1A1A" />
  <link rel="canonical" href="{url}" />
  <link rel="icon" type="image/png" sizes="192x192" href="/assets/logo/favicon-192.png" />
  <meta property="og:type" content="article" />
  <meta property="og:site_name" content="TrackFolks" />
  <meta property="og:locale" content="en_IN" />
  <meta property="og:title" content="{esc(title, quote=True)}" />
  <meta property="og:description" content="{esc(desc, quote=True)}" />
  <meta property="og:url" content="{url}" />
  <meta property="og:image" content="{og}" />
  <meta property="og:image:type" content="image/png" />
  <meta property="og:image:width" content="1780" />
  <meta property="og:image:height" content="910" />
  <meta property="og:image:alt" content="TrackFolks logo with the tagline: Your field team, always connected." />
  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="{esc(title, quote=True)}" />
  <meta name="twitter:description" content="{esc(desc, quote=True)}" />
  <meta name="twitter:image" content="{og}" />
  <meta name="twitter:image:alt" content="TrackFolks logo with the tagline: Your field team, always connected." />
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Sora:wght@400;600;700;800&display=swap" rel="stylesheet">
  {ld}
  <style>{PAGE_CSS}</style>
</head>
<body>
  <header><a href="/"><img src="/assets/logo/tf-logo-96.png" alt="TrackFolks logo" width="34" height="34" /> TrackFolks</a></header>
  <main>
{body}
  </main>
  <footer>
    <p><a href="/">TrackFolks</a> · <a href="/{COMPARE_PATH}">Compare {N} field force tracking apps</a> · <a href="/{HUB_PATH}">Alternatives to the top {N}</a> · <a href="/privacy">Privacy Policy</a></p>
  </footer>
</body>
</html>
'''


def disclosure():
    return (f'<p class="legend">This guide is AI-generated and published by TrackFolks, which is one of the apps covered. If you find an error, '
            f'write to <a href="mailto:{EMAIL}">{EMAIL}</a> and we will correct it. If you want your offering included and you list your pricing openly, write to us and we will add it.</p>')


# ------------------------------------------------------------------ complaints and alternatives
TAG_LABEL = {"reliability": "crashes and login errors", "pricing": "price and renewal complaints",
             "privacy": "always-on or off-duty location complaints", "battery": "battery drain complaints",
             "distance": "distance and GPS accuracy complaints", "support": "support complaints"}
TF_CLAIM = {"reliability": "no crashes reported by the roughly 50 people who have used it so far",
            "privacy": "location is collected only while you are punched in",
            "pricing": "the price is published upfront and capped at $399 a year ($199 in the first year)",
            "support": "the creator gives personal support, and most teams need it only while onboarding",
            "battery": "one location point a minute, uploaded every 15 minutes: as light as it can be while still giving near-real-time data",
            "distance": "distance is measured along the route staff travelled, with stray GPS points removed"}
PRICE_RISK = {"fieldsense"}  # a customer reports a large renewal rise that reviews alone do not show


def _covers(a):
    return {k for k, _ in FEATURES if k != "free" and a["f"][k][0] in ("y", "p")}


def _avg_rating(a):
    return (a["play"][0] + a["ios"][0]) / 2


def _closeness(p, a):
    fx, fa = _covers(p), _covers(a)
    return len(fx & fa) / len(fx | fa) - abs(_avg_rating(a) - _avg_rating(p)) / 5


def all_tags(p):
    tags = []
    for i in p["issues"]:
        for t in i[3]:
            if t not in tags:
                tags.append(t)
    return tags


def main_tags(p):
    return [t for t in all_tags(p) if RATES[p["key"]][t] >= 2.0]


def _eff_rate(a, p, t):
    """The suggested app's reports for tag t; no credit for price complaints unless it publishes a price, has no known rise and is no dearer."""
    ra, rp = RATES[a["key"]][t], RATES[p["key"]][t]
    if t == "pricing" and rp > 0 and (a["y1"] is None or a["key"] in PRICE_RISK or (p["y1"] is not None and a["y1"] > p["y1"])):
        return max(ra, rp)
    return ra


def alternatives(p, limit=3):
    """Other apps ranked by closeness to p (features and store rating) plus how many fewer reports of p's own complaints
    they have. Only apps covering at least half of p's features and clearly better on p's complaints qualify."""
    xs = _covers(p)
    tags = all_tags(p)
    total = sum(RATES[p["key"]][t] for t in tags) or 1.0
    found = []
    for a in P.values():
        if a["key"] == p["key"]:
            continue
        cov = len(xs & _covers(a)) / max(1, len(xs))
        if cov < 0.5:
            continue
        better = sum(max(0.0, RATES[p["key"]][t] - _eff_rate(a, p, t)) for t in tags)
        worse = sum(max(0.0, _eff_rate(a, p, t) - RATES[p["key"]][t]) for t in tags)
        frac = (better - worse) / total
        if frac < 0.3:
            continue
        gains = sorted(((RATES[p["key"]][t] - _eff_rate(a, p, t), t) for t in tags if _eff_rate(a, p, t) < RATES[p["key"]][t]), reverse=True)
        found.append(dict(a=a, score=_closeness(p, a) + 0.5 * frac, have=xs & _covers(a), lack=xs - _covers(a), nx=len(xs), gains=gains))
    found.sort(key=lambda d: -d["score"])
    return found[:limit]


def _rate(a, t):
    r = RATES[a["key"]][t]
    return "none" if r == 0 else f"{r:g}%"


def why_short(d, p):
    """One sentence on why this app is suggested."""
    a = d["a"]
    parts = [f'{TAG_LABEL[t]} ({_rate(a, t)} of its reviews, against {RATES[p["key"]][t]:g}% for {p["name"]})' for _, t in d["gains"][:2]]
    return (f'closest to {p["name"]} in features ({len(d["have"])} of {d["nx"]}) and store rating ({_avg_rating(a):.1f} against {_avg_rating(p):.1f}), '
            f'with far fewer reports of ' + " and ".join(parts))
