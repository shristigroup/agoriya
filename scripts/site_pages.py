"""The generated articles: comparison guide, "alternatives to the top N" hub, and one "alternative to X" page per app."""
import re

from site_core import *  # noqa: F401,F403
from site_core import _rate, _avg_rating  # noqa: F401


# ------------------------------------------------------------------ comparison guide
def build_comparison():
    factors = "".join(f'<div class="factor"><h3><span class="num">{i}</span>{esc(label)}</h3><p>{esc(FACTOR_TEXT[k])}</p></div>'
                      for i, (k, label) in enumerate(FEATURES, 1))
    factors += ('<div class="factor"><h3><span class="num">12</span>Price per user, year 1 and after renewal</h3>'
                '<p>Compare the price of the plan that includes the features you need, and what you pay in the first year against what you pay after renewal. '
                'Some vendors discount the first year or add fees later. Prices here are per user per month for a 30-user team, and ₹95 = $1.</p></div>')
    factors += ('<div class="factor"><h3><span class="num">13</span>App store ratings</h3>'
                '<p>Store ratings are the most credible public signal of how well an app works. Look at the star rating and at the number of ratings: a high score from a handful of reviews means little.</p></div>')
    alts = "".join(f'<li><a href="/{alt_path(p)}">Alternative to {esc(p["name"])}</a></li>' for p in BY_RANK)
    body = f'''    <h1>Comparing the Top {N} Field Force Tracking Apps</h1>
    <p class="meta">Last checked {CHECKED} · {N} most-used attendance and location tracking apps, compared feature by feature</p>
    <img class="hero-img" src="/assets/media/field-force-tracking-apps-comparison.jpg" width="1200" height="654" alt="Diagram of a field force tracking app: a phone sends attendance, location tracking, route calculation and payroll data to a central cloud server" />
    <p>Attendance and field force tracking apps range from general time clocks that added GPS, to Indian attendance and payroll apps, to apps built for field staff. No app wins on every dimension. This guide compares the {N} most-used apps in the category on the features and prices that matter to a team on the road, and puts TrackFolks beside them. For what users complain about and which alternative suits each app, see <a href="/{HUB_PATH}">Alternatives to the Top {N} Attendance and Field Force Tracking Apps</a>.</p>
    <h2>How we picked the top {N}</h2>
    <p>We looked at apps whose job is attendance and location tracking for people who work away from a desk, and ranked them by the number of ratings on Google Play and the App Store combined, because a count of ratings shows real usage better than a star score. Shift schedulers such as When I Work, Homebase and Deputy are left out because they record location only at clock-in, as are broader HR suites and sales force automation tools for consumer-goods distribution. TrackFolks is shown beside the {N} for comparison; its own ratings are too new to rank.</p>
    <h2>The factors that matter</h2>
    <p>These follow the columns of the table below, in the same order.</p>
    <div class="factors">{factors}</div>
    <h2>Top {N} field force tracking apps compared</h2>
    <p class="legend">Green = included. Amber = partial, an add-on, a higher plan or reported by users. Red = not available. Grey = not stated in the vendor's public material, which is not the same as missing. Prices per user per month are green up to $2, amber up to $3 and red above $3. Providers are listed alphabetically.</p>
    <p class="legend"><strong>Score:</strong> every colour-coded cell in a provider's row (the 11 features, the year 1 and renewal prices and the two store ratings, 15 in all) scores green 5, amber 3, red or grey 1, so the maximum is 75. Grey counts as 1 because a feature we could not confirm cannot earn credit, which also means TrackFolks scores 1 for each of its two store ratings because it has none yet. The score weighs every column equally and says nothing about which features matter to you, so use it as a rough guide next to the table.</p>
    {matrix()}
    <p class="legend">Price is the approximate USD per user per month for a 30-user team on the cheapest plan with GPS, with any add-on and base fee included. * FieldSense: worked out from what a FieldSense customer told us (Rs 25,000 for 25 users in year 1, Rs 75,000 after renewal). ✱ Jibble and Hubstaff: the vendor's pages did not list a full price table, so the figures are from third-party sources or exclude an add-on whose price we could not find. We could not find a public price for PagarBook or Unolo. TrackFolks is free for up to 10 users, then $1.05 per user per month, billed yearly, capped at $499 a year ($249 in the first year).</p>
    <h2>Top picks by category</h2>
    <p>The first app in each list is linked so you can go straight to it. Each list shows the top five. Popularity and likeability use Google Play and App Store ratings, so TrackFolks, which has no ratings yet, is not in those two. Feature richness is the score in the table above, and cost effectiveness is the lowest price per user per month after renewal for a 30-user team, among apps that publish a price. A tie on score is broken by popularity. An app can top one list and trail another.</p>
    {top_picks()}
    <h2>What would you pay?</h2>
    {pricing_block()}
    <h2>Alternatives, app by app</h2>
    <p>Each page covers what users of that app report, which alternatives we think fit, and where TrackFolks compares.</p>
    <ul>{alts}</ul>
    {disclosure()}'''
    jsonld = {"@context": "https://schema.org", "@type": "Article", "headline": f"Comparing the Top {N} Field Force Tracking Apps",
              "dateModified": "2026-10-26", "author": {"@type": "Organization", "name": "TrackFolks"},
              "publisher": {"@type": "Organization", "name": "TrackFolks", "url": SITE + "/"},
              "mainEntityOfPage": f"{SITE}/{COMPARE_PATH}"}
    w(COMPARE_PATH, page(f"Comparing the Top {N} Field Force Tracking Apps (2026)",
                         f"The {N} most-used attendance and field force tracking apps compared on GPS, selfie check, routes, geofencing, visits, expenses, free plans and price per user.",
                         COMPARE_PATH, body, jsonld))
    # the first version of this guide was published at an older address: leave a pointer there
    w(f"comparison/{OLD_SLUG}.html", f'''<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8" /><meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Comparing the Top {N} Field Force Tracking Apps</title>
<link rel="canonical" href="{SITE}/{COMPARE_PATH}" />
<meta http-equiv="refresh" content="0; url=/{COMPARE_PATH}" />
<meta name="robots" content="noindex, follow" /></head>
<body><p>This guide has moved: <a href="/{COMPARE_PATH}">Comparing the Top {N} Field Force Tracking Apps</a>.</p></body></html>
''')


# ------------------------------------------------------------------ hub article
THEME_ORDER = ["reliability", "pricing", "privacy", "battery", "distance", "support"]


def best_points(d, p):
    a = d["a"]
    pts = [f'Closest feature-wise ({len(d["have"])} of {d["nx"]} features)',
           f'Similar rating: {_avg_rating(a):.1f} vs {_avg_rating(p):.1f}']
    for _, t in d["gains"][:3]:
        pts.append(f'Fewer {SHORT_TAG[t]} ({_rate(a, t)} vs {RATES[p["key"]][t]:g}%)')
    return pts


def build_hub():
    sections = ""
    rows = ""
    for p in BY_RANK:
        alt = alternatives(p, 1)
        issues_li = "".join(f'<li><strong>{esc(t)}</strong>: {esc(ev)}.</li>' for t, ev, _, _ in p["issues"])
        if alt:
            d = alt[0]
            pts = best_points(d, p)
            best = (f'<div class="best"><strong>Best alternative: <a href="{d["a"]["url"]}" rel="noopener">{esc(d["a"]["name"])}</a></strong>'
                    f'<ul>{"".join(f"<li>{esc(x)}</li>" for x in pts)}</ul>'
                    f'<a href="/{alt_path(p)}">More alternatives to {esc(p["name"])}</a></div>')
            alt_cell = (f'<strong><a href="{d["a"]["url"]}" rel="noopener">{esc(d["a"]["name"])}</a></strong>'
                        f'<ul>{"".join(f"<li>{esc(x)}</li>" for x in pts)}</ul>')
        else:
            best = (f'<div class="best"><strong>Best alternative:</strong> none of the other apps is both close to {esc(p["name"])} and clearly better on these complaints in its reviews, '
                    f'so we do not name one. <a href="/{alt_path(p)}">See the details</a>.</div>')
            alt_cell = "None stands out in the reviews we read"
        price = "not published" if p["y1"] is None else p["price"]["label"] + f" (about {per_user(p).replace(p['mark'], '')} per user per month for 30 users)"
        sections += f'''    <div class="hub-app" id="{p["slug"]}">
      <h3>{esc(p["name"])}</h3>
      <div class="ev">{p["play"][1]:,} Google Play ratings ({p["play"][0]:.1f}) and {p["ios"][1]:,} App Store ratings ({p["ios"][0]:.1f}). Reviews read: latest {p["sample"]["n"]}, {esc(p["sample"]["window"])}.</div>
      <p><strong>What it does:</strong> {esc(", ".join(p["key_features"]))}. <strong>Price:</strong> {esc(price)}.</p>
      <p><strong>Top 3 complaints in app store reviews:</strong></p>
      <ul>{issues_li}</ul>
      {best}
    </div>
'''
        feats = "<ul>" + "".join(f"<li>{esc(f)}</li>" for f in p["key_features"]) + "</ul>"
        comp = "<ul>" + "".join(f"<li>{esc(k)}</li>" for k in KW[p["key"]]) + "</ul>"
        rows += f'<tr><th scope="row">{esc(p["name"])}</th><td>{feats}</td><td>{comp}</td><td>{alt_cell}</td></tr>\n'
    lines = ""
    for t in THEME_ORDER:
        ps = [p for p in BY_RANK if RATES[p["key"]][t] >= 2.0]
        if not ps:
            continue
        worst = max(ps, key=lambda p: RATES[p["key"]][t])
        lines += (f'<li><strong>{esc(cap(TAG_LABEL[t]))}</strong> show up in the reviews of {len(ps)} of {N} apps, most of all {esc(worst["name"])} '
                  f'({RATES[worst["key"]][t]:g}% of the reviews we read). TrackFolks: {esc(TF_CLAIM[t])}.</li>')
    tf_lack = ", ".join(lbl.lower() for k, lbl in FEATURES if k != "free" and TF["f"][k][0] == "x")
    total = sum(p["sample"]["n"] for p in P.values())
    body = f'''    <h1>Alternatives to the Top {N} Attendance and Field Force Tracking Apps</h1>
    <p class="meta">Last checked {CHECKED} · What users complain about in app store reviews, and the best alternative to each app</p>
    <p>Attendance and field force tracking apps are mostly well reviewed, but each has its own sore spots. We read the latest Google Play and App Store reviews of the {N} most-used apps ({total:,} reviews in all), counted what 1 to 3 star reviewers complain about, and picked the best alternative to each, other than TrackFolks. The full comparison of features and prices is in <a href="/{COMPARE_PATH}">Comparing the Top {N} Field Force Tracking Apps</a>.</p>
    <p class="legend">Method: complaints are counted as the share of reviews that are 1 to 3 stars and mention the theme, by keyword and checked by reading. The best alternative is the app closest to the original in features and store rating whose own reviews show far fewer reports of the original's complaints. These are customers' opinions, paraphrased; the samples are small and cover a few months, so treat the differences as indications.</p>
    <h2>App by app</h2>
{sections}
    <h2>Summary</h2>
    <div class="scroll"><table class="summary-table"><thead><tr><th>Provider</th><th>Features</th><th>Top complaints</th><th>Best alternative, and why</th></tr></thead><tbody>
{rows}</tbody></table></div>
    <h2>What the complaints add up to</h2>
    <ul>{lines}</ul>
    <h2>How TrackFolks addresses them</h2>
    <p>TrackFolks is a mobile-first field force tracker: selfie punch-in, live GPS, route replay with distance, a visit check-in form, expense receipts and CSV export for payroll, all managed from the phone. It is free for up to 10 users, then $1.05 per user per month, billed yearly, never more than $499 a year ($249 in the first year), with the renewal price published upfront. Support comes from its creator personally.</p>
    <p>It is a new entrant with no store ratings yet, so these points are the creator's claims rather than review data, and it has gaps: it has no {esc(tf_lack)}, and geofencing is coming soon. But if the complaints above sound familiar, it is worth a shot: it is free for 10 users and needs no talking to anyone to start.</p>
    <div class="cta"><strong>Try TrackFolks free.</strong> Download the app, share your code with your team and start.<br /><a class="btn" href="/#download">Download TrackFolks</a></div>
    {disclosure()}'''
    jsonld = {"@context": "https://schema.org", "@type": "Article", "headline": f"Alternatives to the Top {N} Attendance and Field Force Tracking Apps",
              "dateModified": "2026-10-26", "author": {"@type": "Organization", "name": "TrackFolks"},
              "publisher": {"@type": "Organization", "name": "TrackFolks", "url": SITE + "/"},
              "mainEntityOfPage": f"{SITE}/{HUB_PATH}"}
    w(HUB_PATH, page(f"Alternatives to the Top {N} Attendance and Field Force Tracking Apps",
                     f"The top 3 complaints in app store reviews of {N} attendance and field force tracking apps, and the best alternative to each.",
                     HUB_PATH, body, jsonld))


# ------------------------------------------------------------------ alternative-to-X pages
def build_alt(p):
    n = p["name"]
    sm = p["sample"]
    alts = alternatives(p, 3)
    labels = dict(FEATURES)
    issues = "".join(f'<div class="issue"><h3>{i}. {esc(t)}</h3><div class="ev">{esc(ev)}</div><p>{esc(txt)}</p></div>'
                     for i, (t, ev, txt, _) in enumerate(p["issues"], 1))
    alt_html = ""
    for d in alts:
        a = d["a"]
        lacks = ("It lacks: " + ", ".join(labels[k].lower() for k, _ in FEATURES if k in d["lack"]) + ". ") if d["lack"] else ""
        price = ("does not publish a price" if a["y1"] is None
                 else "is priced at " + a["price"]["label"] + f" (about {per_user(a).replace(a['mark'], '')} per user per month for 30 users)")
        own = [lc1(t[0]) for t in a["issues"][:2]]
        gains = "; ".join(f'{TAG_LABEL[t]}: {_rate(a, t)} of its reviews against {RATES[p["key"]][t]:g}% for {n}' for _, t in d["gains"])
        thin = " Its review sample is small, so treat this with caution." if a["sample"]["n"] < 130 else ""
        alt_html += (f'<div class="alt"><h3><a href="{a["url"]}" rel="noopener">{esc(a["name"])}</a></h3>'
                     f'<div class="ev">{a["play"][1]:,} Google Play ratings ({a["play"][0]:.1f}) and {a["ios"][1]:,} App Store ratings ({a["ios"][0]:.1f}); based on its latest {a["sample"]["n"]} reviews</div>'
                     f'<p><strong>Why we think it is a good alternative:</strong> {esc(why_short(d, p))}.</p>'
                     f'<p>Fewer reports of {esc(n)}\'s complaints: {esc(gains)}.{esc(thin)}</p>'
                     f'<p><strong>Trade-offs:</strong> {esc(lacks)}It {price}. Its own reviewers mostly report {esc(own[0])} and {esc(own[1])}. '
                     f'<a href="/{alt_path(a)}">See its alternatives</a>.</p></div>')
    if not alts:
        alt_html = (f'<p>None of the other {N - 1} apps is both close to {esc(n)} in features and rating and clearly better on these complaints in its reviews, '
                    f'so we do not recommend one here. See the <a href="/{COMPARE_PATH}">full comparison</a> to judge for yourself.</p>')
    tags = main_tags(p) or all_tags(p)[:3]
    fixes = "".join(f'<div class="fix"><h3>{esc(cap(TAG_LABEL[t]))}</h3><p>{esc(cap(TF_CLAIM[t]))}.</p></div>' for t in tags)
    better = []
    if p["y1"] is not None:
        better.append(f'Price: for a 30-user team TrackFolks costs about $0.69 per user per month in the first year and $0.70 after renewal, against about {per_user(p).replace(p["mark"], "")} for {n}'
                      + (" (a figure from a customer)" if p["mark"] == "*" else "") + ".")
    else:
        better.append(f"Price: {n} does not publish a price. TrackFolks publishes its own: free for 10 users, then $1.05 per user per month, billed yearly, never more than $499 a year.")
    for d in alts:
        a = d["a"]
        if a["y1"] is not None and a["y1"] > 0.67:
            better.append(f'Against {a["name"]} at about {per_user(a).replace(a["mark"], "")} per user per month, TrackFolks is cheaper at about $0.70 after the first year.')
    if p["f"]["free"][0] in ("x", "n"):
        better.append(f"Free start: TrackFolks is free for up to 10 users with every feature, while {n} offers "
                      + (p["f"]["free"][1].lower() if p["f"]["free"][0] == "x" else "no free plan we could confirm") + ".")
    better.append("Mobile first: managers do everything from the phone, including exporting CSV reports, with no web dashboard to learn.")
    wins = [labels[k].lower() for k, _ in FEATURES if k != "free" and TF["f"][k][0] == "y" and p["f"][k][0] in ("n", "x")]
    if wins:
        better.append(f'Features {n} does not list that TrackFolks has: {", ".join(wins)}.')
    better_html = "<ul>" + "".join(f"<li>{esc(b)}</li>" for b in better) + "</ul>"
    head = f"<th>Feature</th><th>{esc(n)}</th><th>TrackFolks</th>"
    rows = "".join(f'<tr><th scope="row">{esc(label)}</th>{fcell(*p["f"][k])}{fcell(*TF["f"][k])}</tr>\n' for k, label in FEATURES)
    hl = ",".join([p["key"]] + [d["a"]["key"] for d in alts])
    if p["y1"] is None:
        price_p = (f"We could not find a public price for {n}, so it is not on the chart. TrackFolks is free for 10 users, then $1.05 per user per month, billed yearly, capped at $499 a year ($249 in the first year).")
    else:
        price_p = (f"{n}: {p['price']['label']}. For a 30-user team that is about {per_user(p).replace(p['mark'], '')} per user per month. "
                   f"TrackFolks: free for 10 users, then $1.05 per user per month, billed yearly capped at $499 a year, about $0.69 per user per month in year 1 and $0.70 after renewal for 30 users.")
    body = f'''    <p class="crumbs"><a href="/{HUB_PATH}">Alternatives to the top {N} apps</a> › Alternative to {esc(n)}</p>
    <h1>Alternative to {esc(n)} for Attendance and Field Force Tracking</h1>
    <p class="meta">Last checked {CHECKED} · Based on public prices, store ratings and the latest {sm["n"]} user reviews</p>
    <p>{esc(p["what"])}. It has {p["play"][1]:,} ratings on Google Play ({p["play"][0]:.1f} stars, {p["play"][2]} installs) and {p["ios"][1]:,} on the App Store ({p["ios"][0]:.1f} stars). If you are looking for an alternative, the most common reasons come down to {esc(p["anchor"])}.</p>
    <h2>The top 3 problems {esc(n)} users report</h2>
    <p class="legend">From the latest {sm["n"]} Google Play and App Store reviews ({esc(sm["window"])}); about {sm["low"]}% were 1 to 3 stars. These are customers' opinions, paraphrased, and apps change, so check the latest reviews yourself.</p>
    {issues}
    <h2>Alternatives to {esc(n)}</h2>
    <p class="legend">Chosen from the {N} most-used apps: close to {esc(n)} in features and store rating, and with clearly fewer reports of its complaints in their reviews. Each has its own problems, which are listed with it.</p>
    {alt_html}
    <h2>How TrackFolks addresses these problems</h2>
    <p class="legend">TrackFolks has no store ratings yet, so these are the creator's claims, not review data.</p>
    <div class="fix-grid">{fixes}</div>
    <h2>Where TrackFolks does better</h2>
    {better_html}
    <h2>{esc(n)} and TrackFolks side by side</h2>
    <div class="scroll"><table class="small-table" style="min-width:520px"><thead><tr>{head}</tr></thead><tbody>
{rows}</tbody></table></div>
    <p class="legend">Green = included, amber = partial or higher plan, red = not available, grey = not stated in public material. See the <a href="/{COMPARE_PATH}">full comparison of the top {N} apps</a>.</p>
    <h2>When {esc(n)} is the better choice</h2>
    <p>{esc(p["stay"])}</p>
    <h2>Pricing compared</h2>
    <p>{esc(price_p)}</p>
    {pricing_block(highlight=hl)}
    <div class="cta"><strong>TrackFolks is a new entrant, and worth a shot.</strong> It has no store ratings yet and lacks leave and roster management and biometric attendance, but it is free for up to 10 users, so you can try it with your team without talking to anyone.<br /><a class="btn" href="/#download">Download TrackFolks</a></div>
    <p>Want to see how all the most-used apps compare? Read <a href="/{COMPARE_PATH}">Comparing the Top {N} Field Force Tracking Apps</a> and <a href="/{HUB_PATH}">Alternatives to the Top {N} Attendance and Field Force Tracking Apps</a>.</p>
    {disclosure()}'''
    ld = {"@context": "https://schema.org", "@type": "Article", "headline": f"Alternative to {n} for Attendance and Field Force Tracking",
          "dateModified": "2026-10-26", "author": {"@type": "Organization", "name": "TrackFolks"},
          "publisher": {"@type": "Organization", "name": "TrackFolks", "url": SITE + "/"}, "mainEntityOfPage": f"{SITE}/{alt_path(p)}"}
    a_, b_, c_ = PAIN[p["key"]]
    w(alt_path(p), page(f"Alternative to {n} for Field Force Tracking",
                        f"Alternative to {n}? Users report {a_}, {b_} and {c_}. See better-reviewed options and how TrackFolks compares.",
                        alt_path(p), body, ld))


# ------------------------------------------------------------------ refund policy
def build_refund():
    body = f'''    <h1>Refund Policy</h1>
    <p class="meta">Last updated 30 October 2026</p>
    <p>TrackFolks is free for up to 10 users. If you need more, you pay once for a year of service for your organisation, by card through Stripe. Nothing renews automatically: we send you an invoice before the year ends. This policy applies to every payment.</p>
    <h2>Full refund within 15 days</h2>
    <p>If you ask for a refund within 15 days of paying, we refund 100% of what you paid. We bear Stripe's processing fee, so you get back every dollar.</p>
    <h2>After 15 days: pro-rata refund, less Stripe's fee</h2>
    <p>If you ask after 15 days, we refund the unused part of your year, counted in whole days, minus the processing fee that Stripe charged on your payment. Stripe does not return its fee to us when a payment is refunded, so we deduct it.</p>
    <ul>
      <li><strong>Term:</strong> 365 days from the day you paid.</li>
      <li><strong>Unused days:</strong> the days from the day after your request until the term ends.</li>
      <li><strong>Refund</strong> = amount paid × (unused days ÷ 365) − Stripe's processing fee. If the fee is larger than the pro-rata amount, no refund is due.</li>
    </ul>
    <p><strong>Example:</strong> you paid $249 and ask on day 100 of your term. 265 days are unused, so the pro-rata amount is $249 × 265 ÷ 365 = $180.78. If Stripe's fee on your payment was $8.00 (for illustration only; the fee is on your Stripe receipt), you receive $172.78.</p>
    <h2>How to ask</h2>
    <p>Email <a href="mailto:{EMAIL}">{EMAIL}</a> with your organisation code and, if you can, the email address you paid with. We confirm by email and refund to the card you paid with. Your bank may take 5 to 10 business days to show it.</p>
    <h2>After a refund</h2>
    <p>Your organisation returns to the free plan of up to 10 users from the date of the refund. We do not delete your data because of a refund; you can delete your account from within the app at any time.</p>
    <h2>Renewals</h2>
    <p>Renewals are never automatic. When your year is nearly over we send you an invoice for the next year. If you do not pay it, nothing is charged. The same refund terms apply to each payment.</p>
    <h2>Your legal rights</h2>
    <p>This policy does not limit any rights you have under the law where you live.</p>
    <h2>Contact</h2>
    <p>Ashish Sharma, 141 Barrier Point Road, London, UK – E16 2SE. <a href="mailto:{EMAIL}">{EMAIL}</a></p>'''
    w("refund/index.html", page("Refund Policy | TrackFolks", "TrackFolks refund policy: a full refund within 15 days of payment, and a pro-rata refund by the day after that, less Stripe's processing fee.", "refund/", body))
