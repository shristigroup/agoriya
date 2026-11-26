"""Field force, sales force and field service apps: the data behind the "Alternative to X" pages.

Source: the buyer's guide research of 17 and 23 November 2026 (Google Play, Apple App Store India or US, G2, Capterra, Trustpilot).
This file is the snapshot. The site's own article is the source of truth from here on, so edit this file, not the original document.

Ratings are (rating, count). Prices are as listed by the vendor or, where marked, by third parties; per user per month at Rs 95 = $1, excl. GST.
`cons` lead each page. `alts` are chosen by one rule: for each problem, the same-category app that does not have it (a lower price, a better iPhone rating,
a more stable app); where nothing fits, the highest rated app in the category. TrackFolks (`tf`) is named only on FFA pages where price is a stated problem.
"""
import site_competitors as comp
from site_core import *  # noqa: F401,F403

CHECKED = "November 2026"
CAT_NAME = {"FFA": "field force automation", "SFA": "sales force automation", "FSM": "field service management"}
CAT_FOR = {"FFA": "Attendance and Field Force Tracking", "SFA": "Sales Force Automation", "FSM": "Field Service Management"}
UNIVERSAL = "Battery drain and wrong distance counts are the top complaint about almost every field force app, and none is free of them. Test any app on one real route on your own phones before you commit."

# key: dict(name, cat, url, slug, play, ios, other, price, pros, cons, fits, avoid, alts=[(alt_key, why)], tf=None|why, note)
A = {}


def app(key, name, cat, url, slug, play, ios, other, price, pros, cons, fits, avoid="", alts=(), tf=None, note=""):
    A[key] = dict(key=key, name=name, cat=cat, url=url, slug=slug, play=play, ios=ios, other=other, price=price, pros=pros, cons=cons,
                  fits=fits, avoid=avoid, alts=list(alts), tf=tf, note=note)


# ---------------------------------------------------------------- FFA
app("unolo", "Unolo", "FFA", "https://unolo.com/", "unolo", (4.7, 6470), (3.3, 59), "Capterra 4.6 (35)", "about $2.11 to $2.63",
    ["Easy to use", "Accurate live tracking, timeline, attendance and reports", "Supportive customer care"],
    ["Distance can be off by 5 to 10% on Capterra and more on Google Play (28 of 116 negative reviews with text)", "Battery drain",
     "Gaps in leave approval, expense filters and record history (1 year)", "Some users find it pricey"],
    "mid-size Android-heavy teams that want the most proven app", "your team is mostly on iPhone",
    [("lystloc", "iPhone rating: Lystloc is rated 4.0 on iPhone against Unolo's 3.3, though from only 35 ratings."),
     ("daytrack", "iPhone rating and price: dayTrack is rated 4.2 on iPhone, also from few ratings, and costs about $2.62."),
     ("connect", "Price: Connect My World is about $0.83 per user per month for 20 to 49 users, though its Play reviews are mostly old and its iPhone apps show no ratings.")],
    tf="Price: TrackFolks is $1.05 per user per month with the first 10 users free. It has no leave or shift management and no public reviews yet, so it fits teams that want core tracking at the lowest price.")
app("fieldsense", "FieldSense", "FFA", "https://www.fieldsense.in/", "fieldsense", (3.9, 10900), (2.5, 130), "", "about $2.63",
    ["Live location and route capture", "Attendance with dashboards and muster reports", "Expense claims and visit planning",
     "One of the longest feature lists, including forms, roster and a free tier"],
    ["Wrong distance (about 71 of 373 negative Play reviews, for example 200 km shown as 130 km)", "Battery drain (about 79 of 373)",
     "Bugs, slow sync and weak support", "iPhone rating of 2.5"],
    "cost-conscious Android teams that want breadth", "you pay allowance strictly on km or your team uses iPhones",
    [("unolo", "Rating and price: Unolo is rated 4.7 on Google Play from 6.47K reviews and starts at about $2.11, though its iPhone rating is 3.3."),
     ("dayTrack".lower(), "iPhone: dayTrack is rated 4.2 on iPhone against FieldSense's 2.5, from few ratings."),
     ("lystloc", "iPhone and features: Lystloc is rated 4.0 on iPhone and lists roster, shift and leave management like FieldSense.")])
app("lystloc", "Lystloc", "FFA", "https://www.lystloc.com/", "lystloc", (3.9, 521), (4.0, 35), "Capterra 4.3 (6)", "about $3.67",
    ["Easy to install and use", "Live location, one-touch attendance, analytics, meeting notes and tasks", "Responsive support"],
    ["Distance differences of 5 to 10 km and \"as the crow flies\" counts (14 of 46 negative Play reviews)", "Battery drain",
     "One reviewer says tracking continued after logout", "Fixed pricing with no negotiation, at about $3.67 one of the higher prices among the field force apps here"],
    "small teams that want a simple, hands-on vendor", "you need heavy admin controls",
    [("unolo", "Price and rating: Unolo starts at about $2.11 and is rated 4.7 on Google Play from 6.47K reviews."),
     ("onthego", "Price and rating: OnthegO.ai is about $1.46 to $2.31 in India and rated 4.3 on Google Play from 518 reviews, though its iPhone rating is 3.2."),
     ("connect", "Price: Connect My World is about $0.83 per user per month for 20 to 49 users, though its Play reviews are mostly old and its iPhone apps show no ratings.")],
    tf="Price: TrackFolks is $1.05 per user per month with the first 10 users free, against about $3.67 for Lystloc. It has no public reviews yet and no leave or shift management.")
app("trackofield", "TrackoField", "FFA", "https://trackobit.com/", "trackofield", (3.3, 212), (3.3, 15), "", "about $5 on the annual plan, 10-user minimum ($6 half-yearly, $8 quarterly)",
    ["Broad feature list on paper, including face attendance, forms, roster and payroll", "Real-time tracking works for some users"],
    ["Battery drain (13 of 33 negative reviews)", "Hangs and slows the phone", "Distance mismatches",
     "Thin evidence: about 78 Play reviews read and no G2 or Trustpilot reviews"],
    "teams willing to run a proper trial on their own phones", "you want proven reviews before you buy",
    [("unolo", "Stability: Unolo is rated 4.7 on Google Play from 6.47K reviews, against 3.3 from 212 for TrackoField, and starts at about $2.11."),
     ("onthego", "Price and rating: OnthegO.ai is about $1.46 to $2.31 in India, against about $5 for TrackoField, and is rated 4.3 on Google Play from 518 reviews."),
     ("daytrack", "Price and rating: dayTrack is about $2.62 and rated 4.1 on Google Play and 4.2 on iPhone.")])
app("daytrack", "dayTrack", "FFA", "https://daytrack.in/", "daytrack", (4.1, 868), (4.2, 22), "", "about $2.62 (plus a one-time setup fee of about $5.25 per user)",
    ["Easy to use", "Responsive support (73 positive mentions)", "Attendance, location and task management at a low price"],
    ["Battery drain (16 of 73 negative)", "Login, OTP, sync and update bugs", "Attendance marked absent after punching", "Wrong distance",
     "No expense logging or geofencing"],
    "small teams that need attendance and location only", "you need expense claims or geofencing",
    [("unolo", "Features and rating: Unolo is rated 4.7 on Google Play from 6.47K reviews and lists distance, visit forms and geofencing."),
     ("fieldsense", "Features and price: FieldSense is about $2.63 and lists expense claims, forms, geofencing and a free tier, but is rated 2.5 on iPhone.")])
app("onthego", "OnthegO.ai", "FFA", "https://onthego.ai/", "onthego", (4.3, 518), (3.2, 18), "Capterra 5.0 (8, from 2018 to 2021)", "about $1.46 to $2.31 in India (Rs 139 to Rs 219); international $4.99 and $7.99",
    ["Easy and quick to set up", "Responsive support and fast custom changes at low cost", "Task scheduling and work reports with distance and client OTP confirmation"],
    ["Punch-in and punch-out problems and stuck screens", "Slowness, photo capture interruptions and login trouble after updates",
     "The back-end UI needs work", "iPhone rating of 3.2"],
    "Indian service and field teams that want the vendor to customise", "you need strong iPhone support",
    [("unolo", "Rating: Unolo is rated 4.7 on Google Play from 6.47K reviews."),
     ("daytrack", "iPhone: dayTrack is rated 4.2 on iPhone against OnthegO.ai's 3.2, from few ratings."),
     ("breezefsm", "Hands-on vendor: BreezeFSM is praised for fast, hands-on support and training, but is Android only.")])
app("trackwick", "TrackWick (Trackolap)", "FFA", "https://trackolap.com/", "trackwick", (4.0, 561), None, "G2 5.0 (2)",
    "about $3.16 to $8.42 by plan (third-party listing)",
    ["Easy to use", "Attendance, tracking, kilometres and leave in one app", "Responsive support in many reviews"],
    ["Battery drain and phone heating (6 of 33 negative)", "Crashes and login failures", "Poor after-sales service in some reviews",
     "Pricing seen as high against similar apps"],
    "sales-force tracking where live location is the priority", "",
    [("unolo", "Price and rating: Unolo starts at about $2.11 and is rated 4.7 on Google Play from 6.47K reviews."),
     ("onthego", "Price: OnthegO.ai is about $1.46 to $2.31 in India and rated 4.3 on Google Play from 518 reviews."),
     ("connect", "Price: Connect My World is about $0.83 per user per month for 20 to 49 users, though its Play reviews are mostly old and its iPhone apps show no ratings.")],
    tf="Price: TrackFolks is $1.05 per user per month with the first 10 users free, against about $3.16 to $8.42 for TrackWick by plan. It has no public reviews yet.",
    note="TrackWick's price comes from a third-party listing, not its own site.")
app("breezefsm", "BreezeFSM", "FFA", "https://breezefsm.com/", "breezefsm", (4.1, 22), None, "Capterra 4.7 (15), G2 4.3 (6)", "from about $2.63",
    ["Easy to use", "Fast, hands-on support and training (Capterra service rating 4.9)", "Works offline", "Designed around Indian business needs, according to one reviewer"],
    ["GPS not always accurate enough for travel allowance", "Tracking with a poor network is hard", "The order screen needs filters and better search", "No iPhone app"],
    "Android-only Indian teams that value support", "you need iPhone or a large public track record",
    [("onthego", "Order and visit work: OnthegO.ai is rated 4.3 on Google Play from 518 reviews, has an iPhone app and reports distance with client OTP confirmation."),
     ("unolo", "Accuracy and track record: Unolo is rated 4.7 on Google Play from 6.47K reviews, though its iPhone rating is 3.3."),
     ("daytrack", "iPhone: dayTrack has an iPhone app rated 4.2, from few ratings.")],
    note="BreezeFSM is closer to field force automation with a sales slant than to field service management, despite its name.")

app("connect", "Connect My World", "FFA", "https://www.connectmyworld.in/", "connect-my-world", (4.1, 206), None,
    "Play: supervisor app 4.6 (11), monitor app 3.5 (43); iPhone apps exist but show no rating counts; no Capterra or G2 listing",
    "about $0.83 (Rs 79) for 20 to 49 users; Rs 89 for 6 to 19, Rs 69 for 50 to 199, Rs 65 for 200 and over; billed every 3 months; free 2-week trial",
    ["Live tracking with point-by-point day replay, distance and kilometre logging", "GPS or selfie attendance", "Geofenced visits with arrival alerts and offline forms",
     "All in one per-user price with no tiers"],
    ["Battery drain", "A phone that hangs or slows", "\"km not working properly\" (a 2023 review)", "Hard to uninstall because it runs as a device administrator (the vendor says background running is by design)",
     "The Play reviews read (135) are mostly old, with only three from 2024 and 2025, and there are no Capterra or G2 reviews, so public evidence is thin",
     "The iPhone apps show no ratings"],
    "small and mid-size Indian teams that want tracking, attendance and tasks at one low per-user price", "your team is mostly on iPhone or you want recent public reviews before buying",
    [("unolo", "Recent evidence: Unolo is rated 4.7 on Google Play from 6.47K reviews, updated in November 2026, and starts at about $2.11."),
     ("daytrack", "iPhone: dayTrack has iPhone ratings (4.2 from 22) and is rated 4.1 on Google Play from 868 reviews, at about $2.62."),
     ("lystloc", "iPhone: Lystloc is rated 4.0 on iPhone and 3.9 on Google Play from 521 reviews, at about $3.67.")],
    note="The app is split in three on Google Play: the employee app (Field Task Manager), a supervisor app and a monitor app. The 4.1 rating is the employee app's.")

# ---------------------------------------------------------------- SFA
app("fieldassist", "FieldAssist", "SFA", "https://www.fieldassist.com/", "fieldassist", (4.5, 1120), (3.1, 99), "G2 4.8 (9); Play also lists General Trade 4.1 (3.07K)",
    "quote only (a Capterra listing shows an unclear SGD 9.9 per feature)",
    ["GPS-tagged visits, beat and order flow, outlet coverage reports", "Real-time sales data on one dashboard",
     "Sales force, distributor operations, attendance and outlet management in one platform", "Actively developed, with new AI features"],
    ["Crashes and slowness, including an app closing seconds after launch", "Sync delays, duplicate product entries and inaccurate reports",
     "A learning curve that needs end-user training", "Slow support response in some reviews", "iPhone rating of 3.1, far below Play (4.5)", "No published price"],
    "mid-size and large FMCG companies with distributors and a budget for rollout", "you need a quick self-serve start or a mostly iPhone team",
    [("bizom", "iPhone rating and stability: Bizom is rated 3.9 on iPhone and 4.6 on Google Play from 29.2K reviews."),
     ("delta", "Lighter rollout and support: Delta Sales App is rated 4.3 on Google Play from 784 reviews and is praised for supportive staff and ease of use."),
     ("beatroute", "Onboarding: BeatRoute is praised for good support and onboarding from the back-end team.")])
app("beatroute", "BeatRoute", "SFA", "https://beatroute.io/", "beatroute", None, None, "G2 4.3 (12); Capterra ease of use 4.5",
    "about $3.67 to $7.36 (third-party, unverified)",
    ["Field app for opening accounts, visiting accounts on a map and capturing orders", "Centralised reporting on each rep", "Good support and onboarding from the back-end team"],
    ["Limited mobile customisation", "Archived outlets still appear in route maps", "The OTP step occasionally fails", "Downloaded reports are too broad to filter",
     "No quick-insight dashboard", "A September 2026 Gartner reviewer asked for better GPS accuracy", "No Google Play listing under its own name, so you cannot check ratings on your own phone first"],
    "FMCG teams that want a guided rollout with strong onboarding", "you want public ratings on your own phone before buying",
    [("bizom", "Public track record: Bizom is rated 4.6 on Google Play from 29.2K reviews and 3.9 on iPhone."),
     ("fieldassist", "Ratings: FieldAssist is rated 4.5 on Google Play from 1.12K reviews and 4.8 on G2, though its iPhone rating is 3.1."),
     ("delta", "Ratings: Delta Sales App is rated 4.3 on Google Play from 784 reviews and 4.5 on G2.")],
    note="BeatRoute's prices come from third-party listings and were not verified.")
app("delta", "Delta Sales App", "SFA", "https://deltasalesapp.com/", "delta-sales-app", (4.3, 784), None, "G2 4.5 (13)",
    "contact the vendor (third-party estimates of $10 to $15 are weak)",
    ["Easy to use", "GPS tracking, attendance, beat planning, order booking and visit tracking in one app", "FMCG managers report good return on investment and supportive staff"],
    ["Support and payment problems for international users", "App not opening, wrong location and slowness on some Android 12 phones",
     "No free trial before paying in one older review", "Slow report generation and a confusing interface for one G2 reviewer", "Unclear India presence: it is a Nepal-based developer"],
    "small and mid-size FMCG distributors and sales teams that want a lighter app", "you need deep distributor management or an India-based vendor, which you should confirm first",
    [("bizom", "India presence and scale: Bizom is rated 4.6 on Google Play from 29.2K reviews and reports 750+ brands."),
     ("fieldassist", "Ratings: FieldAssist is rated 4.5 on Google Play and 4.8 on G2, with distributor operations in the platform."),
     ("saleson", "Price: SalesOn publishes a price of about $2.20 to $3.51 per user and covers GST invoicing and Tally.")])
app("bizom", "Bizom", "SFA", "https://bizom.com/", "bizom", (4.6, 29200), (3.9, 206), "Bizom Next on Play 4.5 (1.74K); G2 4.5 (15)", "not published",
    ["A wide feature list: beat optimisation, offline order capture, schemes, distributor management, attendance, leave and van sales", "Reviewers praise real-time data, dashboards and support replies",
     "Vendor claims 750+ brands and 250K+ salespeople"],
    ["Recent Bizom Next reviews report wrong kilometre readings, dashboard figures not updated for 25 days and no \"select all\" for travel claims",
     "iPhone rating of 3.9 for Bizom Next, well below Play (4.5)", "Only 15 reviews on G2", "No published price"],
    "mid-size and large FMCG companies with distributors that want one platform", "you want a published price or a quick self-serve start",
    [("fieldassist", "Review quality: FieldAssist is rated 4.8 on G2 from 9 reviews and 4.5 on Google Play, though its iPhone rating is 3.1."),
     ("saleson", "Published price: SalesOn lists about $2.20 to $3.51 per user on its Play listing and its own site."),
     ("delta", "Lighter app: Delta Sales App is rated 4.3 on Google Play from 784 reviews and 4.5 on G2.")])
app("saleson", "SalesOn", "SFA", "", "saleson", (4.3, 177), None, "iPhone: 5 ratings; no G2 or Capterra reviews", "about $2.20 to $3.51 (Play listing: Rs 209 or Rs 333; own site: Rs 250, 2-user minimum)",
    ["GST invoicing and e-way bill, Tally integration, van sales, distributor management and live location in one app", "Reviewers praise the support team and regular updates", "Low price"],
    ["Needs an internet connection and does not work offline (vendor site)", "Tally auto-sync is priced separately", "The Play listing and the vendor site disagree on price and trial length (2.7 days against 7)",
     "Few public reviews", "The Play app was last updated on 3 Jan 2026"],
    "small distributors and wholesalers with billing and field sales in one place", "your routes have patchy network, or you need a large-brand rollout",
    [("bizom", "Offline use and track record: Bizom lists offline order capture and is rated 4.6 on Google Play from 29.2K reviews."),
     ("delta", "Ratings: Delta Sales App is rated 4.3 on Google Play from 784 reviews and covers beat planning, orders and visit tracking.")])
app("sansales", "SAN SALES (SANeFORCE)", "SFA", "", "san-sales", (4.1, 153), None, "iPhone: 4.8 from 4 ratings in India, none in the US", "quote based",
    ["Attendance, order booking, retailing and call reporting for FMCG reps in one app (2022 Play review)", "The vendor is shipping updates, with a release on 19 Nov 2026"],
    ["August and September 2026 Play reviews say the app hangs, shows errors and is slow", "Reviews of the sibling SAN SFE app complain about battery use and rep tracking",
     "Very few iPhone ratings", "No published price"],
    "Indian FMCG teams that want a vendor with a long track record and are willing to pilot first", "your reps use iPhones, or you need proof of stability",
    [("bizom", "Stability and scale: Bizom is rated 4.6 on Google Play from 29.2K reviews."),
     ("fieldassist", "Ratings: FieldAssist is rated 4.5 on Google Play from 1.12K reviews and 4.8 on G2."),
     ("delta", "Ratings: Delta Sales App is rated 4.3 on Google Play from 784 reviews.")],
    note="SANeFORCE's pharma app, SAN SFE, was last updated on Google Play on 1 Sep 2025 and is not covered here.")
app("salesdiary", "Salesdiary", "SFA", "https://salesdiary.com/", "salesdiary", (4.1, 1360), None, "Capterra 4.7 (15)", "from $12 per user a month (Capterra, third-party; vendor pricing is custom)",
    ["An established app with one of the larger review counts in this category", "Capterra reviewers score ease of use 4.4, value for money 4.4 and features 4.1", "AI-driven route planning and field operations, according to the vendor"],
    ["The Play review sample (2020 to 2024) is mostly negative: hangs, battery drain and constant background location", "Call-log and media permission requests",
     "Attendance time counted from the first activity (the vendor says this follows company policy)", "No iPhone listing of its own found in the India store"],
    "FMCG field teams that want an established app and will test battery and permissions on real phones", "staff are sensitive about background tracking",
    [("bizom", "Stability: Bizom is rated 4.6 on Google Play from 29.2K reviews, though its price is not published."),
     ("saleson", "Price: SalesOn publishes about $2.20 to $3.51 per user, against $12 or more on Capterra for Salesdiary."),
     ("fieldassist", "Ratings: FieldAssist is rated 4.5 on Google Play and 4.8 on G2.")])
app("sfaxpert", "SFAXpert (Marg ERP)", "SFA", "https://margcompusoft.com/", "sfaxpert", (3.8, 347), None, "iPhone listing exists, no rating count shown", "quote based",
    ["A pharma-style reporting app: daily call report, doctor management, chemist orders, expenses, samples and gifts", "One Play reviewer praised real-time GPS tracking and a route map of the field force"],
    ["The lowest Play rating among the SFA apps here (3.8)", "The visible reviews are old (2019 to 2021) and complain about frequent syncing, slowness and rude support", "No published price"],
    "pharma and healthcare reps who mainly need call and expense reporting", "you need current evidence of support quality",
    [("bizom", "Rating: Bizom is rated 4.6 on Google Play from 29.2K reviews."),
     ("fieldassist", "Rating: FieldAssist is rated 4.5 on Google Play and 4.8 on G2."),
     ("delta", "Rating: Delta Sales App is rated 4.3 on Google Play from 784 reviews.")],
    note="These alternatives are built for FMCG, not pharma call reporting. Check that call reports, doctor management and samples are covered before you move.")
app("salesmagna", "SalesMagna SFA", "SFA", "https://salesmagna.com/", "salesmagna", (4.7, 103), (None, 10), "", "quote based, 7-day trial",
    ["Short Play reviews (2024 and 2025) call it easy, fast and employee friendly", "One reviewer compares it favourably with FieldAssist", "A separate DMS app covers distributor management"],
    ["Only 103 Play reviews and 1K+ downloads, so the 4.7 is weak evidence", "Very few iPhone ratings", "No published price"],
    "small FMCG and B2B teams that want a light app", "you need a proven large rollout",
    [("bizom", "Review volume: Bizom is rated 4.6 on Google Play from 29.2K reviews."),
     ("fieldassist", "Review volume: FieldAssist is rated 4.5 on Google Play from 1.12K reviews and 4.8 on G2."),
     ("delta", "Review volume: Delta Sales App is rated 4.3 on Google Play from 784 reviews.")])

# ---------------------------------------------------------------- FSM
app("zoho_fsm", "Zoho FSM", "FSM", "https://www.zoho.com/fsm/", "zoho-fsm", (4.2, 82), (2.7, 11), "G2 4.4 (13)",
    "plans of Rs 1,000, Rs 1,500 and Rs 1,750 a month by appointments, not per user; free plan for 30 appointments and 20 users",
    ["Integrates with other Zoho apps and has endpoints for custom extensions", "Easy to navigate, with agents seeing their schedule and tracking time on the job", "Onboarding sessions and support are praised"],
    ["The mobile app is the weak point: G2 says it needs an overhaul, the App Store lists an old, incomplete interface and an app that would not open on a new iPhone", "Rigid customisation",
     "Photo attachments cannot carry notes", "Rescheduling can be hard"],
    "Indian service businesses already on Zoho that want the lowest entry price", "technicians do most of their work on the phone",
    [("jobber", "Mobile app: Jobber is rated 4.8 on iPhone from 22K ratings and 4.6 on G2 from 546 reviews. Its plans start at $29 a month for one user."),
     ("housecall_pro", "Mobile app: Housecall Pro is rated 4.7 on iPhone from 32K ratings, from $59 a month for one user.")],
    note="Zoho FSM prices are in rupees and by appointments; Jobber and Housecall Pro charge in dollars by plan.")
app("jobber", "Jobber", "FSM", "https://www.getjobber.com/", "jobber", (4.1, 7000), (4.8, 22000), "G2 4.6 (546)",
    "Core $29 a month for 1 user, Connect from $99, Grow from $149, Plus from $399; extra users $29 each",
    ["Quoting, scheduling, invoicing and payments in one back office", "Easy to use, with a large help centre and fast migration", "Fast payment, automated reminders and growing features such as a pipeline and an AI receptionist"],
    ["App stability on Android (63 bug mentions among 150 negative reviews)", "Layout changes with updates and cost complaints (51 price mentions among negatives)",
     "Technicians cannot clock in without signal", "Routing is \"as the crow flies\"", "The phone app is more limited than the web"],
    "small home-service crews; plans start at 1 user", "technicians need to clock in without signal or you want routing beyond straight-line distance",
    [("zoho_fsm", "Price: Zoho FSM starts at Rs 1,000 a month with a free plan for 30 appointments, and is rated 4.2 on Google Play. Its iPhone app is weak (2.7 from 11 ratings)."),
     ("housecall_pro", "Mobile app and price per extra user: Housecall Pro is rated 4.7 on iPhone from 32K ratings, with extra users at $35. It has no listing in the India Play Store.")],
    note="Jobber's prices are plans, not per user, so a larger crew costs more than the entry price suggests.")
app("housecall_pro", "Housecall Pro", "FSM", "https://www.housecallpro.com/", "housecall-pro", None, (4.7, 32000), "G2 4.3 (211); no listing in the India Play Store or App Store",
    "Basic $59 a month for 1 user (no GPS), Essentials $149 for 5 users, Max $299 for 8 users, extra users $35",
    ["Easy to use", "Estimate options and invoice templates", "Customer communication and technician status updates", "QuickBooks sync and responsive support"],
    ["Many features are add-ons, so the price climbs", "Integrations sit behind higher plans", "Card processing fees", "Limited inventory, GPS and VOIP integrations",
     "Little reporting on call sources", "A 30-person team on Max works out to about $35.63 per user per month"],
    "small and mid-size home-service firms that want an all-in-one app", "you need GPS on the cheapest plan or deep reporting",
    [("zoho_fsm", "Price: Zoho FSM starts at Rs 1,000 a month and has a free plan for 30 appointments and 20 users. Its mobile app is rated 2.7 on iPhone, from 11 ratings."),
     ("jobber", "Rating and extra users: Jobber is rated 4.6 on G2 against 4.3, and extra users cost $29 against $35.")])
app("servicetitan", "ServiceTitan", "FSM", "https://www.servicetitan.com/", "servicetitan", None, (3.5, 5700), "G2 4.4 (387); older ServiceTitan Mobile 2.9 (1.7K)", "quote only",
    ["Easy for technicians on G2", "Scheduling and customer management in one place", "Call recording and smarter routing", "One reviewer calls it the most functional of the trades platforms"],
    ["Cost feels high for lean firms", "Complex to learn and implement, and one reviewer says it did not deliver the expected value", "Inconsistent support and vendor lock-in",
     "Technicians dislike the redesigned Field app (clunky, no iPad layout for sales), which is why its iPhone rating is far below G2", "No published price"],
    "large trades businesses with an office team and the budget for implementation", "you are a small crew",
    [("jobber", "Simplicity and price: Jobber publishes its prices from $29 a month and is rated 4.8 on iPhone from 22K ratings and 4.6 on G2."),
     ("housecall_pro", "Simplicity and price: Housecall Pro publishes its prices from $59 a month and is rated 4.7 on iPhone from 32K ratings.")])
app("salesforce_fs", "Salesforce Field Service", "FSM", "https://www.salesforce.com/products/service-cloud/field-service/", "salesforce-field-service", (3.7, 6280), (4.6, 21000), "G2 4.3 (1,253)",
    "an add-on that needs a Service Cloud licence ($25, $100 or $175 per user a month); the add-on price is unconfirmed",
    ["Connects technicians, work orders, scheduling and customer data", "Highly customisable with AI-driven routing", "One job record shared by dispatcher and technician"],
    ["Mobile reliability on Android (bugs in 105 of 230 negative reviews, sync problems and battery drain)", "A July 2026 iPhone review of crash loops",
     "Complex configuration that needs clean skills, travel and parts data", "Hard to debug", "Enterprise pricing"],
    "enterprises already on Salesforce with an admin team", "you want to start in a week",
    [("jobber", "Simplicity and ratings: Jobber is rated 4.8 on iPhone from 22K ratings and 4.6 on G2, with published prices from $29 a month. It is built for small crews, not enterprises."),
     ("servicetitan", "Large trades teams: ServiceTitan is rated 4.4 on G2 from 387 reviews, but it is also complex and quote only."),
     ("zoho_fsm", "Price and Google Play rating: Zoho FSM is rated 4.2 on Google Play against 3.7 and starts at Rs 1,000 a month.")])
app("fieldez", "FieldEZ", "FSM", "https://www.fieldez.com/", "fieldez", (3.1, 15), (None, 9), "G2 4.4 (69), Capterra 4.8 (62)", "$15 to $20 per user a month (G2 listing)",
    ["G2 reviewers praise scheduling and work order management, workflow efficiency, training and customer support", "Capterra reviewers call it easy to use and customisable, with attendance, tracking, offline sync and a customer location map"],
    ["A 3.1 Play rating from 15 reviews and 9 iPhone ratings across two listings cannot show how the app behaves in daily use", "G2 notes occasional sync problems and slow performance at peak times",
     "The Capterra reviews seen date from 2016 to 2018", "The price is a range from G2, not from the vendor"],
    "service businesses that want scheduling, dispatch and attendance and will run a trial before buying", "you need app-store evidence of reliability before you start",
    [("zoho_fsm", "Price and Indian pricing: Zoho FSM starts at Rs 1,000 a month and is rated 4.2 on Google Play from 82 reviews."),
     ("jobber", "Ratings: Jobber is rated 4.1 on Google Play from 7K reviews and 4.8 on iPhone from 22K, though it is built for US-style markets."),
     ("housecall_pro", "Ratings: Housecall Pro is rated 4.7 on iPhone from 32K ratings and 4.3 on G2.")])

ORDER = {"FFA": ["unolo", "fieldsense", "lystloc", "trackofield", "daytrack", "onthego", "trackwick", "breezefsm", "connect"],
         "SFA": ["fieldassist", "beatroute", "delta", "bizom", "saleson", "sansales", "salesdiary", "sfaxpert", "salesmagna"],
         "FSM": ["zoho_fsm", "jobber", "housecall_pro", "servicetitan", "salesforce_fs", "fieldez"]}
for k in A:
    A[k]["alts"] = [(a, t) for a, t in A[k]["alts"] if a in A]
# every alternative must be in the same category as the app it is offered for
for k, v in A.items():
    for a, _ in v["alts"]:
        assert A[a]["cat"] == v["cat"], (k, a)


def path(k):
    return f"comparison/alternative-to-{A[k]['slug']}-field-force-tracking-app.html"


def store(r):
    if r is None:
        return "no listing found"
    rating, n = r
    return f"{n:,} ratings" if rating is None else f"{rating:.1f} ★ ({n:,})"


def link(k):
    a = A[k]
    return f'<a href="/{path(k)}">{esc(a["name"])}</a>'


def site(k):
    a = A[k]
    return f' (<a href="{a["url"]}" rel="noopener nofollow" target="_blank">website</a>)' if a["url"] else ""


def jsonld_guide(headline, p):
    return {"@context": "https://schema.org", "@type": "Article", "headline": headline, "dateModified": "2026-11-23",
            "author": {"@type": "Organization", "name": "TrackFolks"}, "publisher": {"@type": "Organization", "name": "TrackFolks", "url": SITE + "/"},
            "mainEntityOfPage": f"{SITE}/{p}"}


def build(k):
    a = A[k]
    n, cat = a["name"], a["cat"]
    p = path(k)
    top = "comparison/how-to-pick-a-field-force-automation-app.html"
    crumbs = (f'<a href="/{top}">How to Pick a Field Force Automation App</a> › ' if cat == "FFA" else "") + f"Alternatives to {esc(n)}"
    cons = "".join(f"<li>{esc(c)}</li>" for c in a["cons"])
    pros = "".join(f"<li>{esc(c)}</li>" for c in a["pros"])
    rows = f'<tr><th scope="row">Google Play</th><td>{esc(store(a["play"]))}</td></tr><tr><th scope="row">Apple App Store</th><td>{esc(store(a["ios"]))}</td></tr>'
    if a["other"]:
        rows += f'<tr><th scope="row">Other ratings</th><td>{esc(a["other"])}</td></tr>'
    rows += f'<tr><th scope="row">Price</th><td>{esc(a["price"])}</td></tr>'
    cards = ""
    for ak, why in a["alts"]:
        o = A[ak]
        cards += (f'<div class="alt"><h3>{link(ak)}</h3><div class="ev">Google Play: {esc(store(o["play"]))} · App Store: {esc(store(o["ios"]))} · {esc(o["price"])}</div>'
                  f'<p>{esc(why)} Its catch: {esc(o["cons"][0][0].lower() + o["cons"][0][1:])}.{site(ak)}</p></div>')
    if a["tf"]:
        cards += (f'<div class="alt"><h3><a href="/">TrackFolks</a></h3><div class="ev">New listing, no public reviews yet · $1.05 per user per month, first 10 users free</div>'
                  f'<p>{esc(a["tf"])}</p></div>')
    universal = f"<p>{esc(UNIVERSAL)}</p>" if cat == "FFA" else ""
    stay = f"<p>{esc(n)} fits {esc(a['fits'])}." + (f" Avoid it if {esc(a['avoid'])}." if a["avoid"] else "") + "</p>"
    note = f'<p class="legend">{esc(a["note"])}</p>' if a["note"] else ""
    tf_disc = ("This guide is published by TrackFolks, which makes a field force app. It is named here only where it answers a problem listed above, and it has no public reviews yet."
               if a["tf"] else "This guide is published by TrackFolks, which makes a field force app. TrackFolks is not recommended on this page because it does not answer the problems above.")
    others = "".join(f'<li>{link(o)}</li>' for o in ORDER[cat] if o != k)
    title = f"Alternatives to {n} for {CAT_FOR[cat]}"
    body = f'''    <p class="crumbs">{crumbs}</p>
    <h1>{esc(title)}</h1>
    <p class="meta">Last checked {CHECKED} · Based on Google Play, App Store, G2, Capterra and Trustpilot reviews</p>
    <p>People choose {esc(n)} for what it does well, then leave it for a handful of problems. This page lists those problems, the ratings behind them and the {esc(CAT_NAME[cat])} apps that do not share them.</p>
    <h2>What {esc(n)} does well</h2>
    <ul>{pros}</ul>
    <h2>What people complain about</h2>
    <ul>{cons}</ul>
    {universal}
    <p class="legend">Counts such as "14 of 46 negative reviews" are shares of the negative reviews read, not of all users. Google Play's "Most relevant" list leans negative, so these show what is common, not how many users are affected.</p>
    <h2>{esc(n)} ratings and price</h2>
    <div class="scroll"><table class="small-table" style="min-width:420px"><tbody>{rows}</tbody></table></div>
    {note}
    <h2>Better alternatives to {esc(n)}</h2>
    <p>Each is in the same category and avoids a problem above. Where nothing avoids a problem, we suggest the highest rated app.</p>
    {cards}
    <h2>When {esc(n)} is still the right choice</h2>
    {stay}
    <p>See all four categories in the <a href="/comparison/field-tracking-software-buyers-guide.html">buyer's guide to field tracking software</a>.</p>
    <h2>More {esc(CAT_NAME[cat])} apps</h2>
    <ul>{others}</ul>
    <p class="legend">{esc(tf_disc)} Prices are per user per month on an annual plan at ₹95 = $1, excluding GST, and change often, so confirm with the vendor. No app was tested hands-on.</p>'''
    w(p, page(title, f"What people like and dislike about {n}, how it is rated, and the {CAT_NAME[cat]} apps that avoid its problems.", p, body, jsonld_guide(title, p)))


def build_all():
    for k in A:
        build(k)
