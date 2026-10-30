"""Single source of truth for the comparison pages, alternative pages and the landing page.

Edit the numbers here and re-run scripts/build_site.py. Prices are public list prices
(USD, annual billing where offered) checked in October 2026; rupees at Rs 95 = $1.
"""

CHECKED = "October 2026"
EMAIL = "developer@shristigroup.com"
SITE = "https://tf.shristigroup.com"
TOP10_SLUG = "top-10-field-force-tracking-apps"
OLD_SLUG = "how-to-choose-a-field-force-tracking-app"

USERS = [10, 20, 30, 50, 100]

# --- Feature columns for the comparison matrix --------------------------------------------
# cell codes: y = yes, p = partial / plan-gated / add-on / reported, x = no, n = not stated
FEATURES = [
    ("selfie", "Selfie / face check at punch-in"),
    ("live", "Live location"),
    ("route", "Route history and distance"),
    ("geofence", "Geofencing"),
    ("visits", "Customer visit logging"),
    ("expenses", "Expense claims"),
    ("leave", "Leave / roster"),
    ("payroll", "Payroll"),
    ("offline", "Works offline"),
    ("biometric", "Biometric / QR attendance"),
    ("free", "Free plan"),
]

FACTOR_TEXT = {
    "selfie": "A selfie or face check shows who punched in, which reduces buddy punching. Check whether it is included in the plan you pay for.",
    "live": "Live location answers \"where is this person right now?\" It is often an add-on or a top-tier feature, and usually works only while the person is punched in.",
    "route": "A recorded route answers \"where did they go today, and how far?\" It matters for mileage claims, proof of visits and beat compliance, and it needs continuous tracking.",
    "geofence": "Geofencing restricts punches to a site, or punches people in and out automatically when they enter or leave one. It is usually a mid-tier feature.",
    "visits": "Field sales and service teams need to log each customer visit with a location, notes and photos. General time clocks often lack this.",
    "expenses": "Expense claims, receipts and mileage reimbursement save the back-and-forth of paper bills.",
    "leave": "HR-led businesses want leave balances and rosters in the same tool. Field-first apps often leave these out.",
    "payroll": "Built-in payroll is a big feature; many teams only need clean attendance data exported for their payroll tool.",
    "offline": "With poor coverage, an app that cannot queue data loses it. Check what happens without a signal: some apps queue punches, others only queue locations.",
    "biometric": "Biometric devices, QR codes and kiosks suit fixed sites. Field teams mostly punch in on their own phones.",
    "free": "\"Free\" often means a trial, or a free plan without GPS. Look at the user limit and what is switched off.",
}

# --- Providers -----------------------------------------------------------------------------
# rank = order by combined Google Play + App Store ratings count (usage evidence)
P = {}


def provider(key, **kw):
    P[key] = dict(key=key, **kw)


provider(
    "quickbooks", name="QuickBooks Time", slug="quickbooks-time", rank=1,
    what="QuickBooks Time (the app is called QuickBooks Workforce) is Intuit's time tracking product",
    url="https://quickbooks.intuit.com/time-tracking/", pricing_url="https://quickbooks.intuit.com/time-tracking/pricing/",
    play=(4.65, 68786, "5M+"), ios=(4.65, 197750, "US"),
    f=dict(selfie=("n", "Not stated"), live=("y", "Who's working map"), route=("p", "GPS mileage, Elite plan"),
           geofence=("p", "Elite plan"), visits=("n", "Not stated"), expenses=("n", "Not stated"),
           leave=("y", "Time off, scheduling"), payroll=("y", "Payroll product, syncs"), offline=("y", "Yes"),
           biometric=("n", "Not stated"), free=("x", "30-day trial")),
    key_features=["GPS time tracking", "Who's working map", "Geofence and mileage (Elite)", "Scheduling and time off", "Payroll"],
    price=dict(kind="formula", base=20, per=10, label="$20 a month base fee + $10 per user (Premium); geofencing needs Elite at $40 + $12"),
    y1=10.67, renew=10.67, mark="",
    sample=dict(n=200, low=74, window="August to October 2026"),
    issues=[
        ("Crashes, slow loading and clock-in failures after updates", "about half of the 1 to 3 star reviews",
         "Reviewers describe a redesign that made clocking in slower, apps that need restarting, and clock-ins that fail or fire by themselves.", ["reliability"]),
        ("Timesheets and data not syncing", "about 1 in 10 of the low-star reviews",
         "Reviewers say the pay period does not update, particularly after clocking in from a computer.", ["reliability"]),
        ("Location tracked \"indefinitely\" and hard-to-reach support", "a recurring theme in the lowest-rated reviews",
         "Some reviewers object to always-on location permission, and others report accounts deactivated with no phone line to fix it.", ["privacy", "support"]),
    ],
    stay="You need payroll, shift scheduling, geofenced job sites or the QuickBooks accounting integration today. TrackFolks has none of those yet.",
    anchor="a base fee plus $10 or more per user, and location features on higher plans",
)

provider(
    "pagarbook", name="PagarBook", slug="pagarbook", rank=2,
    what="PagarBook is an Indian staff attendance, salary and payroll app, with a separate Geo product for field staff",
    url="https://pagarbook.com/", pricing_url="https://pagarbook.com/geo/",
    play=(4.37, 91913, "10M+"), ios=(3.1, 455, "India"),
    f=dict(selfie=("y", "Selfie attendance"), live=("y", "Geo product"), route=("y", "Geo route timeline"),
           geofence=("n", "Not stated"), visits=("y", "OTP-confirmed visits"), expenses=("n", "Not stated"),
           leave=("y", "Leave, salary"), payroll=("y", "Built in"), offline=("n", "Not stated"),
           biometric=("y", "Biometric machine"), free=("p", "Free basic app")),
    key_features=["Selfie and geo-tagged attendance", "Live location and route timeline (Geo)", "Visits with OTP confirmation", "Salary and payroll", "Biometric attendance"],
    price=None, y1=None, renew=None, mark="",
    sample=dict(n=200, low=60, window="August to October 2026 on Google Play, 2024 to 2026 on the App Store"),
    issues=[
        ("Crashes, errors and data that disappears after updates", "about a third of the 1 to 3 star reviews",
         "Reviewers describe the app not responding, historical data not visible after an update, and records disrupted.", ["reliability"]),
        ("Renewals, premium plans and support", "frequent among the lowest-rated reviews",
         "Several reviewers complain about renewal follow-up calls, being asked for a premium plan to keep access to their data, and an app that is \"free\" only at the start.", ["pricing", "support"]),
        ("Missing automation", "about 1 in 10 of the low-star reviews",
         "Reviewers mention leave not being deducted automatically, no lock to a single device, and no API.", []),
    ],
    stay="You need salary and payroll calculation, leave management or biometric machines in the same app. TrackFolks exports CSV for payroll but does not calculate it.",
    anchor="a callback-only price and renewal pressure reported by reviewers",
)

provider(
    "connecteam", name="Connecteam", slug="connecteam", rank=3,
    what="Connecteam is a US employee management app with time clock, scheduling, chat and forms",
    url="https://connecteam.com/", pricing_url="https://connecteam.com/pricing/",
    play=(4.76, 30285, "1M+"), ios=(4.86, 61257, "US"),
    f=dict(selfie=("n", "Not stated"), live=("p", "Breadcrumbs"), route=("p", "Breadcrumb trail"),
           geofence=("y", "Yes"), visits=("n", "Not stated"), expenses=("n", "Not stated"),
           leave=("y", "Scheduling, time off"), payroll=("p", "Integrations"), offline=("x", "No (reported)"),
           biometric=("n", "Not stated"), free=("y", "Up to 10 users")),
    key_features=["GPS clock-in and clock-out", "Breadcrumb trail", "Geofencing", "Scheduling and time off", "Chat and forms"],
    price=dict(kind="connecteam", label="$29 a month flat for the first 30 users, then $0.80 per user"),
    y1=0.97, renew=0.97, mark="",
    sample=dict(n=200, low=49, window="July to October 2026 on Google Play, November 2025 to October 2026 on the App Store"),
    issues=[
        ("Bugs, lag and login problems", "about 4 in 10 of the 1 to 3 star reviews",
         "Reviewers describe an admin app that will not load, shifts missing from the schedule, and notifications that arrive late or too often.", ["reliability"]),
        ("Always-on background location", "about 1 in 10 of the low-star reviews, more in the lowest-rated",
         "Reviewers object to being asked to allow location tracking all the time, including when not working.", ["privacy"]),
        ("Unexpected charges and add-on fees", "a recurring theme among the lowest-rated reviews",
         "Some reviewers say they were charged much more than the price they expected and that features need upgrades.", ["pricing"]),
    ],
    stay="You need shift scheduling, team chat, forms or a free plan for a small team in one tool. TrackFolks has no scheduling or chat.",
    anchor="tiered pricing that reviewers say turns out higher than advertised",
)

provider(
    "salarybox", name="SalaryBox", slug="salarybox", rank=4,
    what="SalaryBox is an Indian staff attendance, payroll and HR app",
    url="https://www.salarybox.in/", pricing_url="https://www.salarybox.in/pricing",
    play=(4.31, 11547, "1M+"), ios=(3.66, 391, "India"),
    f=dict(selfie=("y", "AI selfie"), live=("p", "Add-on, Rs 100"), route=("p", "Reported"),
           geofence=("y", "Yes"), visits=("y", "Meetings"), expenses=("y", "Yes"),
           leave=("y", "Yes"), payroll=("y", "Built in"), offline=("n", "Not stated"),
           biometric=("y", "Machine, QR kiosk"), free=("x", "7-day trial")),
    key_features=["AI selfie attendance", "Geofence attendance", "Live location (add-on)", "Client meetings and expenses", "Payroll and leave"],
    price=dict(kind="per", per=1.842, label="Rs 75 per user (Business) + Rs 100 per user for live location = about $1.84"),
    y1=1.84, renew=1.84, mark="",
    sample=dict(n=200, low=16, window="September to October 2026 on Google Play, September 2025 to October 2026 on the App Store"),
    issues=[
        ("Renewal price hikes and \"not free\"", "the most common complaint in the 1 to 3 star reviews, 7 of the 14 lowest-rated",
         "Reviewers say the price nearly doubled at renewal, that a first-year discount does not carry over, and that the app is not free once set up.", ["pricing"]),
        ("App not opening after updates", "about 3 in 10 of the low-star reviews",
         "Reviewers on iPhone describe the app opening and closing straight away after an update.", ["reliability"]),
        ("After-sale support and salary errors", "about 1 in 7 of the low-star reviews",
         "Reviewers report that support is only reachable at renewal, and some report mistakes in salary calculations.", ["support"]),
    ],
    stay="You need built-in payroll, leave management, biometric or QR attendance and geofencing today. TrackFolks has none of those built in.",
    anchor="renewal price increases that reviewers describe, plus a paid live-location add-on",
)

provider(
    "fieldsense", name="FieldSense", slug="fieldsense", rank=5,
    what="FieldSense is an Indian field force management and sales automation app",
    url="https://www.fieldsense.in/", pricing_url="https://www.fieldsense.in/",
    play=(3.87, 10880, "100K+"), ios=(2.45, 130, "India"),
    f=dict(selfie=("n", "Not stated"), live=("y", "Yes"), route=("y", "Yes"),
           geofence=("n", "Not stated"), visits=("y", "Visit management"), expenses=("y", "Yes"),
           leave=("y", "Yes"), payroll=("n", "Not stated"), offline=("y", "Offline mode"),
           biometric=("y", "Biometric integration"), free=("x", "Paid")),
    key_features=["Location tracking", "Visit management", "Expense claims", "Leave and attendance rules", "Offline mode"],
    price=dict(kind="fieldsense", label="Rs 1,000 per user per year in the first year, Rs 3,000 after renewal (customer-reported)"),
    y1=0.88, renew=2.63, mark="*",
    sample=dict(n=129, low=68, window="June 2025 to October 2026 on Google Play, up to 2026 on the App Store"),
    issues=[
        ("Crashes, hangs and sync problems", "about a quarter of the 1 to 3 star reviews",
         "Reviewers describe an app that hangs, stops accepting entries and needs reinstalling.", ["reliability"]),
        ("Distance shown much lower than travelled", "about 1 in 5 of the low-star reviews",
         "Reviewers report kilometres under-counted, one saying 90 km travelled showed as 23 km.", ["distance"]),
        ("Battery drain and tracking after logout", "about 1 in 6 of the low-star reviews",
         "Reviewers report heavy battery use, and a couple say location kept being used after they logged out or off duty.", ["battery", "privacy"]),
    ],
    stay="You need leave management, biometric integration or a mature sales-force workflow today. TrackFolks has no leave management and no biometric support.",
    anchor="a price that a customer says tripled after the first year",
)

provider(
    "clockify", name="Clockify", slug="clockify", rank=6,
    what="Clockify is a time tracker and timesheet app with GPS on its paid plans",
    url="https://clockify.me/", pricing_url="https://clockify.me/pricing",
    play=(4.52, 3001, "1M+"), ios=(4.62, 4545, "US"),
    f=dict(selfie=("n", "Not stated"), live=("p", "Last locations, Pro plan"), route=("p", "Route points, Pro plan"),
           geofence=("n", "Not stated"), visits=("n", "Not stated"), expenses=("y", "Yes"),
           leave=("y", "Time off"), payroll=("n", "Not stated"), offline=("p", "Offline mode"),
           biometric=("n", "Not stated"), free=("p", "5 users, no GPS")),
    key_features=["Timer and timesheets", "Projects and billable time", "GPS locations (Pro)", "Time off", "Kiosk"],
    price=dict(kind="per", per=7.99, label="$7.99 per user per month (Pro, the plan with GPS)"),
    y1=7.99, renew=7.99, mark="",
    sample=dict(n=200, low=55, window="September 2025 to October 2026"),
    issues=[
        ("Crashes, sign-in loops and logouts", "about 4 in 10 of the 1 to 3 star reviews",
         "Reviewers describe being unable to log in, being kicked out and asked to create an account again, and failures in offline mode.", ["reliability"]),
        ("Features moved out of the free plan", "about 1 in 10 of the low-star reviews",
         "Reviewers say features they used for free were removed or moved to paid plans.", ["pricing"]),
        ("Built for timesheets, not field teams", "inferred from the feature set",
         "GPS, route points and kiosk are paid extras on a timer-and-timesheet product.", []),
    ],
    stay="You track project hours, billable time and timesheets for desk or hybrid teams. TrackFolks does not do project time tracking.",
    anchor="GPS only on the paid Pro plan and a free plan that has been cut back",
)

provider(
    "jibble", name="Jibble", slug="jibble", rank=7,
    what="Jibble is a time and attendance app with a free plan for unlimited users",
    url="https://jibble.io/", pricing_url="https://jibble.io/pricing",
    play=(4.64, 5224, "500K+"), ios=(4.84, 1601, "US"),
    f=dict(selfie=("y", "Face recognition"), live=("p", "Ultimate plan"), route=("p", "Timesheet locations"),
           geofence=("y", "Yes"), visits=("n", "Not stated"), expenses=("n", "Not stated"),
           leave=("y", "Yes"), payroll=("y", "Payroll-ready timesheets"), offline=("y", "Yes"),
           biometric=("y", "NFC, RFID, QR, PIN"), free=("y", "Unlimited users")),
    key_features=["Facial recognition and selfie", "GPS and geofencing", "Live location (Ultimate)", "Offline use", "Payroll-ready timesheets"],
    price=dict(kind="per", per=7.99, label="about $7.99 per user per month (Ultimate, the plan with live location; third-party figure)"),
    y1=7.99, renew=7.99, mark="✱",
    sample=dict(n=200, low=26, window="January to October 2026 on Google Play, 2024 to 2026 on the App Store"),
    issues=[
        ("Errors, logouts and auto clock-out", "about a third of the 1 to 3 star reviews",
         "Reviewers report being clocked out within a minute without doing anything, errors when clocking in, and being unable to log back in.", ["reliability"]),
        ("Always-on location, face scan and battery", "in the lowest-rated reviews",
         "Reviewers mention that always-on location and a full face scan are required to clock in, and that the battery drains and the phone gets hot after an update.", ["privacy", "battery"]),
        ("Live location is a paid extra", "from Jibble's own plan pages and reviewers",
         "Live location needs the Ultimate plan, and reviewers say GPS can be slow to lock or inaccurate.", ["pricing", "distance"]),
    ],
    stay="You want a free plan for unlimited users, offline clock-in, kiosk mode or payroll-ready timesheets. TrackFolks has no kiosk and no unlimited free plan.",
    anchor="live location and extra features that sit on the paid plan",
)

provider(
    "unolo", name="Unolo", slug="unolo", rank=8,
    what="Unolo is an Indian field force management app",
    url="https://unolo.com/", pricing_url="https://unolo.com/pricing",
    play=(4.74, 6311, "100K+"), ios=(3.27, 59, "India"),
    f=dict(selfie=("p", "Facelock, separate product"), live=("y", "Real-time location"), route=("y", "Distance travelled"),
           geofence=("p", "Auto attendance, Basic plan"), visits=("y", "Sites and clients"), expenses=("y", "Conveyance claims"),
           leave=("y", "Yes"), payroll=("n", "Not stated"), offline=("n", "Not stated"),
           biometric=("p", "Facelock"), free=("x", "14-day trial")),
    key_features=["Real-time location tracking", "Distance travelled", "Attendance and leave", "Expense and conveyance claims", "Field sales and service workflows"],
    price=None, y1=None, renew=None, mark="",
    sample=dict(n=110, low=23, window="June to October 2026 on Google Play, a handful on the App Store"),
    issues=[
        ("Battery drain", "about a quarter of the 1 to 3 star reviews",
         "Reviewers say the app runs constantly in the background and drains the battery fast, including after updates.", ["battery"]),
        ("Crashes and permission loops", "about 1 in 7 of the low-star reviews",
         "Reviewers describe the app closing on open and repeatedly asking for settings changes.", ["reliability"]),
        ("Distance that does not match the trip", "about 1 in 9 of the low-star reviews",
         "Reviewers report distance not calculated, or a gap of 25 to 30 km against the speedometer over 150 km.", ["distance"]),
    ],
    stay="You need leave management, a task builder or Unolo's field sales and service workflows. TrackFolks does not have those.",
    anchor="no public price on its pricing page",
)

provider(
    "truein", name="Truein", slug="truein", rank=9,
    what="Truein is an Indian face-recognition time and attendance app for field, contract and multi-site workforces",
    url="https://truein.com/", pricing_url="https://www.truein.com/pricing",
    play=(4.42, 2937, "500K+"), ios=(3.85, 75, "India"),
    f=dict(selfie=("y", "Face recognition"), live=("p", "Live tracking add-on"), route=("n", "Not stated"),
           geofence=("y", "GPS geofencing"), visits=("p", "Activity punch"), expenses=("n", "Not stated"),
           leave=("p", "Add-on"), payroll=("p", "Payroll-ready timesheets"), offline=("y", "Offline clock-in"),
           biometric=("y", "Face recognition"), free=("x", "14-day trial")),
    key_features=["Face recognition clock-in with GPS geofencing", "Offline clock-in with automatic sync", "Live GPS tracking (add-on)", "Shift scheduling and time off", "Payroll-ready timesheets"],
    price=dict(kind="truein", label="Rs 250 per user per year + a Rs 69,000 a year base fee (Time Capture), plus Rs 200 per user per year for live tracking"),
    y1=2.41, renew=2.41, mark="",
    sample=dict(n=118, low=22, window="April 2025 to October 2026 on Google Play, 18 reviews on the App Store"),
    issues=[
        ("Tedious attendance corrections and a time picker that fails", "a handful of the 26 low-star reviews",
         "Reviewers say regularising attendance takes a lot of effort and the time selector often does not register what they pick.", ["reliability"]),
        ("OTP not received and login problems", "a handful of the low-star reviews",
         "Reviewers report one-time passwords that do not arrive and an app that does not work properly.", ["reliability"]),
        ("Not suited to field staff, and location errors", "a few of the low-star reviews",
         "Some reviewers say the app does not suit ground-level field workers, and others report frequent location problems.", ["distance"]),
    ],
    stay="You need face-recognition attendance with offline clock-in, shift scheduling and attendance policies for contract or multi-site staff. TrackFolks has no face check, no scheduling and no biometric support.",
    anchor="a Rs 69,000 a year base fee and attendance corrections that reviewers find tedious",
)

provider(
    "hubstaff", name="Hubstaff", slug="hubstaff", rank=10,
    what="Hubstaff is a US time tracking app with GPS, geofenced job sites and timesheets for distributed and field teams",
    url="https://hubstaff.com/", pricing_url="https://hubstaff.com/pricing",
    play=(3.0, 950, "100K+"), ios=(4.54, 1537, "US"),
    f=dict(selfie=("n", "Not stated"), live=("p", "Locations add-on"), route=("p", "Route history, Locations add-on"),
           geofence=("p", "Job sites, Locations add-on"), visits=("p", "Job site attendance with notes and photos"), expenses=("n", "Not stated"),
           leave=("n", "Not stated"), payroll=("p", "Integrated payroll (reported)"), offline=("n", "Not stated"),
           biometric=("n", "Not stated"), free=("x", "14-day trial")),
    key_features=["GPS time tracking and geofenced job sites", "Live team map and route history (Locations add-on)", "Timesheets and reports", "Tasks and projects", "Payroll (reported)"],
    price=dict(kind="per", per=10.0, label="$10 per user per month (Team plan, annual); the Locations add-on needed for GPS is extra and its price was not found"),
    y1=10.0, renew=10.0, mark="✱",
    sample=dict(n=197, low=44, window="December 2021 to October 2026 on Google Play and the App Store"),
    issues=[
        ("Bugs, forced logouts and updates that break features", "about a third of the 1 to 3 star reviews",
         "Reviewers describe being logged out every time the app closes, timers that rewind after an update, and screens that stop working.", ["reliability"]),
        ("Billing surprises and add-ons", "several of the lowest-rated reviews",
         "Reviewers say add-ons appeared on their bill without being requested, that refunds were refused, and that paid add-ons did not do what they expected.", ["pricing"]),
        ("Confusing for small teams, and slow support", "a recurring theme in the lowest-rated reviews",
         "Reviewers find it hard to navigate and configure for a small business, and some say support did not help when the app stopped working.", ["support"]),
    ],
    stay="You need desktop time tracking, screenshots, project and task time, or payroll alongside GPS job sites. TrackFolks is a mobile app with no desktop tracking or project time.",
    anchor="GPS features that need a paid add-on, and billing surprises that reviewers describe",
)

provider(
    "timeero", name="Timeero", slug="timeero", rank=11,
    what="Timeero is a US GPS time and mileage tracking app",
    url="https://timeero.com/", pricing_url="https://timeero.com/pricing",
    play=(4.74, 812, "50K+"), ios=(4.69, 1656, "US"),
    f=dict(selfie=("p", "Photo at clock-in"), live=("n", "Not stated"), route=("y", "Route map, breadcrumbs, playback"),
           geofence=("p", "Pro plan"), visits=("n", "Not stated"), expenses=("p", "Mileage"),
           leave=("n", "Not stated"), payroll=("p", "Payroll integrations"), offline=("y", "Yes (reported)"),
           biometric=("n", "Not stated"), free=("x", "Trial")),
    key_features=["GPS tracking with route breadcrumbs and playback", "Automatic mileage calculation", "Geofencing (Pro plan)", "Scheduling and job and task costing", "Payroll integrations"],
    price=dict(kind="per", per=5.0, label="$5 per user per month (Basic, annual); geofencing needs Pro at $7.50"),
    y1=5.0, renew=5.0, mark="",
    sample=dict(n=183, low=31, window="June 2022 to October 2026 on Google Play, 2018 to 2026 on the App Store"),
    issues=[
        ("Crashes, forced logouts and updates that break things", "about 3 in 10 of the 1 to 3 star reviews",
         "Reviewers describe an app that will not open after an update or on older phones, logs them out, and clocks them out when the signal drops.", ["reliability"]),
        ("Mileage and location that do not match the trip", "a recurring theme in the low-star reviews",
         "Reviewers report only a quarter of trips tracked, wrong kilometres, and locations that were read incorrectly and affected their pay.", ["distance"]),
        ("Always-on location, battery drain and billing", "several of the lowest-rated reviews",
         "Reviewers object to tracking when not clocked in and to battery use, and some complain about annual-only billing and a paid admin seat.", ["privacy", "battery", "pricing"]),
    ],
    stay="You need automatic mileage reimbursement, job costing and scheduling with GPS. TrackFolks measures distance but does not do mileage reimbursement or job costing.",
    anchor="mileage that does not match trips, and always-on location",
)

# --- TrackFolks -----------------------------------------------------------------------------
TF = dict(
    key="trackfolks", name="TrackFolks", mark="",
    f=dict(selfie=("y", "Selfie punch-in"), live=("y", "Yes"), route=("y", "Route replay, daily distance"),
           geofence=("p", "Coming soon"), visits=("y", "Check-in form"), expenses=("y", "Receipts"),
           leave=("x", "Not available"), payroll=("p", "CSV export for payroll"),
           offline=("p", "Location gathered offline; punch-in needs a connection"),
           biometric=("x", "Not available"), free=("y", "Up to 10 users")),
    key_features=["Selfie punch-in", "Live location", "Route replay and daily distance", "Visit check-in form", "Expense receipts and CSV export"],
    y1=0.69, renew=0.70,
)

# Claims the creator has confirmed; used verbatim-in-spirit on the site.
CLAIMS = {
    "pricing": ("Pricing you can plan around",
                "Free for 10 users, then $1.05 per user per month, billed yearly, never more than $499 a year ($249 in your first year). The renewal price is published upfront, and the same cap holds for teams beyond 100 users."),
    "privacy": ("Privacy first",
                "Location is collected only while you are punched in. There is no tracking when staff are off duty."),
    "distance": ("Accurate distance measurement",
                 "Distance is measured along the route staff actually travelled, with stray GPS points filtered out and the route snapped to roads."),
    "battery": ("Easy on the battery",
                "One location point a minute, uploaded every 15 minutes: as light as it can be while still showing managers near-real-time data, about 15 minutes behind."),
    "reliability": ("Reliable",
                    "No crashes reported by the roughly 50 people who have used the app so far, from in-person feedback and TestFlight crash data."),
    "mobile": ("Mobile first",
               "Everything is done from the phone, including exporting CSV reports, so managers never need a dashboard to get work done."),
    "support": ("Personal support from the creator",
                "The creator answers on WhatsApp personally. Most teams need support only while onboarding, because the app is self-serve."),
    "try": ("Try it yourself",
            "Free for up to 10 users. Download the app, share your code and start, with no need to talk to anyone."),
}


# Short pain-point labels used in each alternative page's description.
PAIN = {
    "quickbooks": ["crashes after updates", "timesheet sync problems", "always-on location"],
    "pagarbook": ["crashes after updates", "renewal pressure", "support delays"],
    "connecteam": ["bugs and lag", "always-on location", "unexpected charges"],
    "salarybox": ["renewal price hikes", "the app not opening", "poor after-sale support"],
    "fieldsense": ["crashes and hangs", "wrong distance", "battery drain"],
    "clockify": ["sign-in loops", "free plan cuts", "no field focus"],
    "jibble": ["auto clock-out errors", "battery drain", "paid live location"],
    "unolo": ["battery drain", "crashes", "wrong distance"],
    "truein": ["tedious corrections", "OTP and login problems", "poor fit for field staff"],
    "hubstaff": ["bugs and logouts", "billing surprises", "slow support"],
    "timeero": ["crashes and logouts", "mileage accuracy", "always-on location"],
}

# Share of ALL sampled reviews that are 1-3 stars and mention crashes, errors or login failures (keyword count, Oct 2026).
CRASH = {"quickbooks": 36.5, "pagarbook": 22.0, "connecteam": 20.0, "salarybox": 4.5, "fieldsense": 16.3,
         "clockify": 21.0, "jibble": 9.0, "unolo": 3.6, "truein": 3.4, "hubstaff": 16.2, "timeero": 9.8}

# Share of ALL sampled reviews (latest ~100 per store, Oct 2026) that are 1-3 stars AND mention each theme.
# Keyword counts, spot-checked by reading the low-star reviews; SalaryBox pricing is from reading them (8 of 200).
RATES = {
    "quickbooks":  dict(reliability=37.5, pricing=0.0, privacy=2.5, battery=1.5, distance=2.0,  support=4.5),
    "pagarbook":   dict(reliability=22.5, pricing=5.5, privacy=0.5, battery=2.0, distance=1.5,  support=8.5),
    "connecteam":  dict(reliability=20.0, pricing=2.0, privacy=5.5, battery=2.0, distance=0.5,  support=3.0),
    "salarybox":   dict(reliability=4.5,  pricing=4.0, privacy=0.0, battery=0.0, distance=0.0,  support=2.5),
    "fieldsense":  dict(reliability=16.3, pricing=0.0, privacy=1.6, battery=11.6, distance=13.2, support=3.9),
    "clockify":    dict(reliability=21.0, pricing=2.0, privacy=1.5, battery=0.0, distance=0.0,  support=0.0),
    "jibble":      dict(reliability=9.0,  pricing=1.5, privacy=1.0, battery=0.5, distance=0.5,  support=1.0),
    "unolo":       dict(reliability=3.6,  pricing=0.0, privacy=0.9, battery=5.5, distance=2.7,  support=0.0),
    "truein":      dict(reliability=3.4,  pricing=0.0, privacy=0.0, battery=0.0, distance=0.8,  support=0.0),
    "hubstaff":    dict(reliability=16.2, pricing=3.0, privacy=1.0, battery=1.0, distance=0.0,  support=2.5),
    "timeero":     dict(reliability=9.8,  pricing=2.0, privacy=2.2, battery=2.7, distance=2.2,  support=0.0),
}


# Very short complaint keywords for the summary table (one per issue, same order as each provider's issues).
KW = {
    "quickbooks": ["crash", "data sync", "indefinite location tracking"],
    "pagarbook": ["crash, data loss", "steep renewal price", "missing automation"],
    "connecteam": ["buggy", "indefinite location tracking", "billing surprise"],
    "salarybox": ["steep renewal price", "crash", "poor support"],
    "fieldsense": ["crash", "incorrect distance", "battery drain"],
    "clockify": ["crash, login loop", "free plan cuts", "no field focus"],
    "jibble": ["buggy", "indefinite location tracking", "paid live location"],
    "unolo": ["battery drain", "crash", "incorrect distance"],
    "truein": ["bad UI", "login errors", "poor fit for field staff"],
    "hubstaff": ["buggy", "billing surprise", "bad UI"],
    "timeero": ["crash", "incorrect distance", "indefinite location tracking"],
}
SHORT_TAG = {"reliability": "crash complaints", "pricing": "renewal / billing complaints", "privacy": "indefinite-location complaints",
             "battery": "battery-drain complaints", "distance": "incorrect-distance complaints", "support": "support complaints"}
