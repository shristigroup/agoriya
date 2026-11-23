#!/usr/bin/env python3
"""Generates the refund and terms pages, the sitemap and llms.txt sections,
and patches the generated blocks of the landing page (price chart and competitor table from scripts/site_competitors.py, keywords). The old /comparison/ pages (scripts/site_data.py)
are not regenerated any more; their build calls are commented out in main.

Run from the repo root:  python3 scripts/build_site.py
Modules: site_data.py (numbers and text), site_core.py (shared pieces), site_pages.py (the articles), site_css.py.
"""
import os
import re

from site_core import *  # noqa: F401,F403
from site_css import LANDING_CSS, ENTERPRISE
from site_pages import build_comparison, build_hub, build_alt, build_refund, build_terms
import site_competitors as comp
import site_compare
import site_guide
import site_buyers_guide


# older "Alternative to X" pages for apps the guide does not cover (HR and workforce tools); the guide pages replace the rest
OLD_ALTS = [alt_path(p) for p in BY_RANK if alt_path(p) not in {site_guide.path(k) for k in site_guide.A}]


def build_sitemap():
    urls = [("", True), (TOP_PATH, False), (site_buyers_guide.GUIDE_PATH, False)] + [(site_guide.path(k), False) for k in site_guide.A] + [(p, False) for p in OLD_ALTS] + [("privacy/", False), ("refund/", False), ("terms/", False)]
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"', '        xmlns:video="http://www.google.com/schemas/sitemap-video/1.1">']
    for path, video in urls:
        out += ["  <url>", f"    <loc>{SITE}/{path}</loc>", "    <lastmod>2026-10-26</lastmod>"]
        if video:
            out += ["    <video:video>",
                    "      <video:thumbnail_loc>https://i.ytimg.com/vi/8dkmj1N7yp8/hqdefault.jpg</video:thumbnail_loc>",
                    "      <video:title>Track Your Team's Attendance &amp; Travel Location | TrackFolks mobile app demo</video:title>",
                    "      <video:description>A short walkthrough of the TrackFolks field force tracking app: selfie punch-in, live GPS location and route replay, customer visit logs and the manager's team view, on Android and iPhone.</video:description>",
                    "      <video:player_loc>https://www.youtube.com/embed/8dkmj1N7yp8</video:player_loc>",
                    "    </video:video>"]
        out.append("  </url>")
    out.append("</urlset>")
    w("sitemap.xml", "\n".join(out) + "\n")


def build_llms():
    path = os.path.join(ROOT, "llms.txt")
    s = open(path).read()
    a, b = s.index("## Pricing (as of"), s.index("## Links")
    names = ", ".join(p["name"] for p in BY_RANK)
    L = [f"## Pricing (as of {site_compare.CHECKED_NEW})", "",
         "- The first 10 users are free, with all features including GPS.",
         "- Beyond 10 users: $1.05 (₹100) per user per month, billed yearly, capped at $499 per year for the organisation, including beyond 100 users.",
         "- First-year offer: the yearly cap is $249 instead of $499. The renewal price ($499 cap) is published upfront.",
         "- No base fee and no paid add-ons for GPS or route tracking. About $0.69 per user per month in year 1 and $0.70 after renewal for a 30-user team; about $0.42 for a 100-user team after the first year.",
         "- Enterprise: the same $499 per year usage cost, plus one-time costs for data localisation (choosing your data region), on-premise or own-cloud hosting, and custom features.",
         f"- In our comparison of {site_compare.NC} field force automation apps ({site_compare.CHECKED_NEW}, public prices, annual billing, cheapest plan with route and distance features, excluding GST), TrackFolks has the lowest published price per user. "
         "Competitors per user per month: " + ", ".join(f"{c['name']} {comp.usd(c['cost']).replace('<br>', ', ')}" for c in site_compare.COMPETITORS) + ". "
         "Truein also has a mandatory base fee of about $726 a year; some vendors have setup fees or minimum seat counts.",
         "", "## What TrackFolks offers", "",
         "- Selfie punch-in, live GPS location, route replay with daily distance, customer visit check-in form, expense receipts, team view with reporting hierarchy, and CSV export used for payroll.",
         "- Location is collected only while the user is punched in (no off-duty tracking). One location point a minute, uploaded every 9 minutes, so managers see near-real-time data with about a 9 minute delay and the battery impact is kept low.",
         "- Everything is managed from the mobile app (no web dashboard by design). Location data is gathered offline and synced later; punch-in needs a connection so the manager is notified straight away.",
         "- No crashes have been reported by the roughly 50 people who have used the app so far. Personal support from the creator, mostly needed only during onboarding.",
         "- Not available: leave or roster management and biometric or QR attendance. Geofencing is coming soon. TrackFolks is a new entrant with no store ratings yet.",
         "", "## Alternatives and comparisons", "",
         f"The guide compares {site_compare.NC} field force automation apps: {', '.join(c['name'] for c in site_compare.COMPETITORS)}. Each has its own 'Alternative to' page:", ""]
    for cat in ("FFA", "SFA", "FSM"):
        for k in site_guide.ORDER[cat]:
            L.append(f"- [Alternative to {site_guide.A[k]['name']} ({cat})]({SITE}/{site_guide.path(k)})")
    for p in BY_RANK:
        if alt_path(p) in OLD_ALTS:
            L.append(f"- [Alternative to {p['name']}]({SITE}/{alt_path(p)})")
    L += ["", f"- [{site_buyers_guide.GUIDE_TITLE}]({SITE}/{site_buyers_guide.GUIDE_PATH}): four categories and 36 field tracking apps compared on ratings, reviews, price and fit.",
          f"- [{site_compare.TOP_TITLE}]({SITE}/{TOP_PATH}): who needs field force automation, must-have and good-to-have features, how to compare prices, and {site_compare.NC} apps compared.", "",
          "Where TrackFolks is a good fit: field sales, service and delivery teams that want selfie attendance, live GPS, route and distance reports, customer visit logs and expense receipts at the lowest price, managed entirely from a phone.",
          "Where another app is a better fit: teams that need leave or roster management, biometric or QR attendance, built-in payroll, shift scheduling or geofenced job sites today.", ""]
    s = s[:a] + "\n".join(L) + "\n" + s[b:]
    s = re.sub(r"- \[(?:Comparing the Top \d+ Field Force Tracking Apps|Top \d+ Field Force Automation Software Compared)\]\([^)]*\): [^\n]*\n",
               f"- [{site_compare.TOP_TITLE}]({SITE}/{TOP_PATH}): who needs field force automation, must-have and good-to-have features, and {site_compare.NC} apps compared.\n", s)
    open(path, "w").write(s)


# ------------------------------------------------------------------ landing page
def guides_footer():
    """Footer links to every article: the two guides, then the 'Alternative to' pages by category."""
    def a(href, text):
        return f'<a href="/{href}">{esc(text)}</a>'
    rows = [("Guides", [a(site_buyers_guide.GUIDE_PATH, "Buyer's guide to field tracking software"), a(TOP_PATH, "How to pick a field force automation app")])]
    for cat, label in (("FFA", "Field force automation"), ("SFA", "Sales force automation"), ("FSM", "Field service management")):
        rows.append((f"Alternatives, {label.lower()}", [a(site_guide.path(k), site_guide.A[k]["name"]) for k in site_guide.ORDER[cat]]))
    old = [a(alt_path(p), p["name"]) for p in BY_RANK if alt_path(p) in OLD_ALTS]
    rows.append(("Alternatives, HR and workforce tools", old))
    return "\n".join(f'    <p style="margin-top:8px;"><strong>{esc(t)}:</strong> ' + " · ".join(links) + "</p>" for t, links in rows)


def patch_landing():
    path = os.path.join(ROOT, "index.html")
    s = open(path).read()
    # the price chart between the markers comes from site_competitors.py
    s = re.sub(r"(<!-- cmp:start -->\n).*?(\n\s*<!-- cmp:end -->)", lambda m: m.group(1) + comp.section_html(esc) + m.group(2), s, flags=re.S)
    s = re.sub(r"(<!-- chart:start -->\n).*?(\n\s*<!-- chart:end -->)", lambda m: m.group(1) + comp.chart_block() + m.group(2), s, flags=re.S)
    s = re.sub(r"(<!-- guides:start -->\n).*?(\n\s*<!-- guides:end -->)", lambda m: m.group(1) + guides_footer() + m.group(2), s, flags=re.S)
    kw = ", ".join(p["name"] + " alternative" for p in BY_RANK) + ", field force tracking app India, field employee tracker, sales team attendance app"
    s = re.sub(r'<meta name="keywords" content="[^"]*" />', lambda _: f'<meta name="keywords" content="{kw}" />', s)
    open(path, "w").write(s)


if __name__ == "__main__":
    # The /comparison/ pages (old, wider provider set) are no longer regenerated; the files stay as they are.
    # for r in RETIRED:
    #     if os.path.exists(os.path.join(ROOT, r)):
    #         os.remove(os.path.join(ROOT, r))
    # build_comparison()
    # build_hub()
    # for p in P.values():
    #     build_alt(p)
    site_compare.build_all()
    site_guide.build_all()
    site_buyers_guide.build()
    build_refund()
    build_terms()
    build_sitemap()
    build_llms()
    patch_landing()
    print("built refund + terms + sitemap + llms + landing")
