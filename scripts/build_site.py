#!/usr/bin/env python3
"""Generates the competitor comparison page (scripts/site_competitors.py), the refund and terms pages, the sitemap and llms.txt sections,
and patches the generated blocks of the landing page (price chart, FAQ, keywords). The old /comparison/ pages (scripts/site_data.py)
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


def build_sitemap():
    urls = [("", True), (COMPARE_PATH, False), (HUB_PATH, False)] + [(alt_path(p), False) for p in BY_RANK] + [("privacy/", False), ("refund/", False), ("terms/", False)]
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
    L = ["## Pricing (as of October 2026)", "",
         "- The first 10 users are free, with all features including GPS.",
         "- Beyond 10 users: $1.05 (₹100) per user per month, billed yearly, capped at $499 per year for the organisation, including beyond 100 users.",
         "- First-year offer: the yearly cap is $249 instead of $499. The renewal price ($499 cap) is published upfront.",
         "- No base fee and no paid add-ons for GPS or route tracking. About $0.69 per user per month in year 1 and $0.70 after renewal for a 30-user team; about $0.42 for a 100-user team after the first year.",
         "- Enterprise: the same $499 per year usage cost, plus one-time costs for data localisation (choosing your data region), on-premise or own-cloud hosting, and custom features.",
         f"- In our comparison of the {N} most-used attendance and field force tracking apps ({CHECKED}, public prices, GPS included, 30-user team), TrackFolks has the lowest published cost per user. "
         "Connecteam is about $0.97, SalaryBox about $1.84, Truein about $2.41, Timeero about $5, Clockify about $7.99, Jibble about $7.99, Hubstaff about $10 (without its GPS add-on) and QuickBooks Time about $10.67 per user per month. "
         "A FieldSense customer reports Rs 1,000 per user per year in year 1 and Rs 3,000 after renewal. PagarBook and Unolo do not publish prices.",
         "", "## What TrackFolks offers", "",
         "- Selfie punch-in, live GPS location, route replay with daily distance, customer visit check-in form, expense receipts, team view with reporting hierarchy, and CSV export used for payroll.",
         "- Location is collected only while the user is punched in (no off-duty tracking). One location point a minute, uploaded every 9 minutes, so managers see near-real-time data with about a 9 minute delay and the battery impact is kept low.",
         "- Everything is managed from the mobile app (no web dashboard by design). Location data is gathered offline and synced later; punch-in needs a connection so the manager is notified straight away.",
         "- No crashes have been reported by the roughly 50 people who have used the app so far. Personal support from the creator, mostly needed only during onboarding.",
         "- Not available: leave or roster management and biometric or QR attendance. Geofencing is coming soon. TrackFolks is a new entrant with no store ratings yet.",
         "", "## Alternatives and comparisons", "",
         f"TrackFolks is compared with the {N} most-used attendance and field force tracking apps: {names}. Each has its own page covering the top 3 complaints in its app store reviews, which alternatives we think fit (other than TrackFolks), and how TrackFolks compares:", ""]
    for p in BY_RANK:
        L.append(f"- [Alternative to {p['name']}]({SITE}/{alt_path(p)})")
    L += ["", f"- [Alternatives to the Top {N} Attendance and Field Force Tracking Apps]({SITE}/{HUB_PATH}): the top complaints for each app and the best alternative to each, with a summary table.",
          f"- [Comparing the Top {N} Field Force Tracking Apps]({SITE}/{COMPARE_PATH}): feature by feature, price per user in year 1 and after renewal, and app store ratings.", "",
          "Where TrackFolks is a good fit: field sales, service and delivery teams that want selfie attendance, live GPS, route and distance reports, customer visit logs and expense receipts at the lowest price, managed entirely from a phone.",
          "Where another app is a better fit: teams that need leave or roster management, biometric or QR attendance, built-in payroll, shift scheduling or geofenced job sites today.", ""]
    s = s[:a] + "\n".join(L) + "\n" + s[b:]
    s = re.sub(r"- \[Comparing the Top \d+ Field Force Tracking Apps\]\([^)]*\): [^\n]*\n",
               f"- [Comparing the Top {N} Field Force Tracking Apps]({SITE}/{COMPARE_PATH}): {N} most-used apps compared on features, price per user and store ratings.\n", s)
    open(path, "w").write(s)


# ------------------------------------------------------------------ landing page
FAQ = [
    ("How much does TrackFolks cost compared with other field force tracking apps?",
     "The first 10 users are free. Beyond that it is $1.05 (₹100) per user per month, billed yearly, capped at $499 a year, or $249 in the first year. For a 30-user team that is about $252 a year ($249 in the first year), compared with about $348 on Connecteam, $663 on SalaryBox, $868 on Truein, $1,800 on Timeero, $2,876 on Clockify and $3,840 on QuickBooks Time, based on public pricing in " + CHECKED + "."),
    ("Is TrackFolks an alternative to QuickBooks Time, Connecteam, Clockify, Jibble, Hubstaff or Timeero?",
     "Those are time tracking and team management apps from outside India that include GPS, often on higher plans or with add-ons. TrackFolks is built for field staff: selfie punch-in, live GPS, route replay with distance, customer visit check-ins and expense receipts. They offer scheduling, payroll, offline clock-in and geofencing that TrackFolks does not have yet."),
    ("How does TrackFolks compare with SalaryBox, PagarBook, FieldSense, Unolo and Truein?",
     "These are Indian apps. SalaryBox and PagarBook add leave management, payroll and biometric or QR attendance, and Truein adds face-recognition attendance with offline clock-in, none of which TrackFolks has; FieldSense and Unolo are field-first, like TrackFolks. On price, SalaryBox is about ₹175 ($1.84) per user per month with live location and has no free plan, Truein charges a ₹69,000 yearly base fee, PagarBook and Unolo do not publish prices, and a FieldSense customer reports ₹1,000 per user per year in year 1 and ₹3,000 after renewal. TrackFolks is free for 10 users and then $1.05 per user per month (billed yearly), capped at $499 a year."),
    ("Does TrackFolks drain the battery or track staff when they are off duty?",
     "No. TrackFolks collects one location point a minute and uploads every 9 minutes, which is as light as it can be while still showing managers near-real-time data. Location is collected only while a user is punched in; background permission is needed so tracking continues while the app is in the background during a shift."),
    ("Does TrackFolks work on iPhone and Android? Do I need a web dashboard?",
     "TrackFolks has apps for both Android and iPhone, and everything is done from the app, including exporting CSV reports for payroll. There is no web dashboard by design: managers never need one to get their work done."),
    ("What can TrackFolks not do yet?",
     "TrackFolks has no leave or roster management and no biometric or QR attendance. Geofencing is coming soon. Payroll is handled by exporting a CSV, and location is gathered offline and synced later, while punch-in needs a connection so the manager is notified straight away. It is also a new entrant with no store ratings yet."),
    ("What do users complain about in other attendance and field force tracking apps?",
     "In app store reviews of the most-used apps, the most common complaints are crashes and login errors after updates, price and renewal surprises, always-on location tracking, battery drain, inaccurate distance, and slow support. See our article on alternatives to the top attendance and field force tracking apps."),
    ("Where can I see all these apps compared side by side?", None),
]


def faq_html():
    cmp_html = (f'Our <a href="/{COMPARE_PATH}" style="color:var(--red);font-weight:600;">comparison of the top {N} field force tracking apps</a> lists selfie check, live location, '
                'route history, geofencing, visits, expenses, leave, payroll, offline use, biometric attendance, free plans, price per user in year 1 and after renewal, and app store ratings. '
                f'<a href="/{HUB_PATH}" style="color:var(--red);font-weight:600;">Alternatives to the top {N} apps</a> covers what each app\'s users complain about and the best alternative to each, '
                f'and every app has its own page, such as <a href="/{alt_path(P["salarybox"])}" style="color:var(--red);font-weight:600;">alternative to SalaryBox</a> and '
                f'<a href="/{alt_path(P["quickbooks"])}" style="color:var(--red);font-weight:600;">alternative to QuickBooks Time</a>.')
    items = ""
    for q, a in FAQ:
        ans = cmp_html if a is None else esc(a)
        items += ('      <div class="faq-item">\n'
                  f'        <button class="faq-q">{esc(q)} <i class="faq-chevron">▾</i></button>\n'
                  f'        <div class="faq-a">{ans}</div>\n'
                  '      </div>\n\n')
    return items


def faq_json():
    import json
    cmp_txt = (f"Our comparison of the top {N} field force tracking apps lists selfie check, live location, route history, geofencing, visits, expenses, leave, payroll, "
               "offline use, biometric attendance, free plans, price per user in year 1 and after renewal, and app store ratings, and our article on alternatives covers what each app's users complain about and the best alternative to each.")
    ents = [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": (cmp_txt if a is None else a)}} for q, a in FAQ]
    return json.dumps({"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": ents}, ensure_ascii=False, indent=2)


def build_competitors():
    w("competitor-comparison/index.html", page(
        "Competitor Comparison: Field Force Tracking Apps in India | TrackFolks",
        "Close-fit field force tracking apps in India compared on price per user, setup fee, GPS, attendance, distance and visit logging. Filter by feature.",
        "competitor-comparison/", comp.page_body(esc), extra_css=comp.PAGE_CSS_EXTRA))


def patch_landing():
    path = os.path.join(ROOT, "index.html")
    s = open(path).read()
    # the price chart between the markers comes from site_competitors.py
    s = re.sub(r"(<!-- chart:start -->\n).*?(\n\s*<!-- chart:end -->)", lambda m: m.group(1) + comp.chart_block() + m.group(2), s, flags=re.S)
    m = re.search(r'(<div class="faq-list">\n)(.*?)(    </div>\n  </div>\n\n  <!-- ── Contact ── -->)', s, re.S)
    s = s[:m.start(2)] + "\n" + faq_html() + s[m.end(2):]
    m = re.search(r'(<!-- FAQPage structured data for Google rich snippets -->\s*<script type="application/ld\+json">\s*)\{.*?\}(\s*</script>)', s, re.S)
    s = s[:m.start()] + m.group(1) + faq_json() + m.group(2) + s[m.end():]
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
    build_refund()
    build_terms()
    # build_competitors()  # the competitor comparison page comes after the home page
    build_sitemap()
    build_llms()
    patch_landing()
    print("built refund + terms + sitemap + llms + landing")
