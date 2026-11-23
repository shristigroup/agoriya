"""The buyer's guide across all four categories (field force, sales force, field service, HR and workforce tools).

The text lives in scripts/guide_content.txt, a snapshot of the November 2026 research, and is the source of truth for the site.
Edit that file, then run scripts/build_site.py. The structured per-app data for the "Alternative to X" pages is in site_guide.py.
"""
import html
import os
import re

from site_core import *  # noqa: F401,F403
import site_compare
import site_guide as guide

GUIDE_PATH = "comparison/field-tracking-software-buyers-guide.html"
GUIDE_TITLE = "Field Force, Sales Force or Field Service? A Buyer's Guide to Field Tracking Software (2026)"
SRC = os.path.join(os.path.dirname(__file__), "guide_content.txt")
LABELS = ("Pros", "Cons", "Cons and gaps", "Fits", "Limit", "Location tracking", "What the pricing page confirms", "GPS pricing")
# paragraph that introduces a list -> how many following paragraphs are its items
LISTS = {"Before you pay any of them:": 4, "Three reading notes:": 4, "What was read": 5, "Limits": 9, "Pages opened for this guide": 5}
ESSENTIAL_COUNTS = iter([6, 5, 6, 5])  # FFA, SFA, FSM, HR and workforce
BY_NAME = {a["name"]: k for k, a in guide.A.items()}


# Small inline marks for the review platforms and price, used in place of the words "Play", "iPhone", "G2", "Capterra", "Trustpilot" and "Price".
APPLE_PATH = "M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z"
ICONS = {
    "Play": ("Google Play", '<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><path d="M3.6 2.4 13.2 12 3.6 21.6c-.4-.2-.6-.6-.6-1.1V3.5c0-.5.2-.9.6-1.1z" fill="#00A0FF"/><path d="m16.4 8.8-3.2 3.2 3.2 3.2 3.7-2.1c.9-.5.9-1.7 0-2.2z" fill="#FFC107"/><path d="M13.2 12 3.6 2.4c.3-.2.8-.2 1.2.1l11.6 6.3z" fill="#00E676"/><path d="M13.2 12 3.6 21.6c.4.2.9.2 1.2-.1l11.6-6.3z" fill="#F44336"/></svg>'),
    "iPhone": ("Apple App Store", '<svg viewBox="0 0 24 24" width="14" height="14" fill="currentColor" aria-hidden="true"><path d="APPLE"/></svg>'),
    "G2": ("G2", '<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="#FF492C"/><text x="12" y="16" text-anchor="middle" font-size="10" font-weight="800" fill="#fff" font-family="Arial,sans-serif">G2</text></svg>'),
    "Capterra": ("Capterra", '<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><rect x="1" y="1" width="22" height="22" rx="5" fill="#044D80"/><path d="M6 17 18 6v7l-5 2.5z" fill="#FF9D28"/><path d="M6 17 13 15.5 11 19z" fill="#68C5ED"/></svg>'),
    "Trustpilot": ("Trustpilot", '<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><rect x="1" y="1" width="22" height="22" rx="4" fill="#00B67A"/><path d="m12 4.5 2 5.6h5.6L15 13.5l1.8 5.5-4.8-3.4L7.2 19 9 13.5 4.4 10.1H10z" fill="#fff"/></svg>'),
    "Price": ("Price per user per month", '<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><circle cx="12" cy="12" r="11" fill="#F5A623"/><text x="12" y="17" text-anchor="middle" font-size="14" font-weight="800" fill="#fff" font-family="Arial,sans-serif">$</text></svg>'),
}
ICONS["iPhone"] = (ICONS["iPhone"][0], ICONS["iPhone"][1].replace("APPLE", APPLE_PATH))


def icon(k):
    name, svg = ICONS[k]
    return f'<span class="pi" role="img" aria-label="{name}" title="{name}">{svg}</span>'


def ev_html(t):
    """The rating line of an entry: the platform words at the start of each sentence become icons."""
    t = html.escape(t, quote=False)
    return re.sub(r"(^|(?<=[.;] ))(Play|iPhone|G2|Capterra|Trustpilot|Price):?(?= )", lambda m: m.group(1) + icon(m.group(2)), t)


def slug(t, used):
    s = re.sub(r"[^a-z0-9]+", "-", t.lower()).strip("-")[:60]
    n, base = 1, s
    while s in used:
        n += 1
        s = f"{base}-{n}"
    used.add(s)
    return s


def parse(text):
    lines = text.split("\n")
    blocks, i = [], 0
    while i < len(lines):
        ln = lines[i]
        if not ln.strip():
            i += 1
        elif ln.startswith("### "):
            blocks.append(("h3", ln[4:])); i += 1
        elif ln.startswith("## "):
            blocks.append(("h2", ln[3:])); i += 1
        elif ln.startswith("# "):
            i += 1
        elif i + 1 < len(lines) and lines[i + 1].startswith(" | "):
            rows, row = [], []
            while i < len(lines) and lines[i].strip():
                t = lines[i]
                if t.strip() == "|":
                    rows.append(row); row = []
                else:
                    row.append(t[3:] if t.startswith(" | ") else t)
                i += 1
            blocks.append(("table", rows))
        else:
            blocks.append(("p", ln)); i += 1
    # turn the item paragraphs that follow a list introducer into lists
    out, i = [], 0
    while i < len(blocks):
        k, v = blocks[i]
        n = None
        if k == "p" and v.startswith("Essential features, in order of importance"):
            n = next(ESSENTIAL_COUNTS)
        elif k == "p" and v in LISTS:
            n = LISTS[v]
        out.append((("h3" if k == "p" and v in LISTS and v.endswith(("read", "Limits", "guide")) else k), v))
        if n:
            out.append(("list", [b[1] for b in blocks[i + 1:i + 1 + n]]))
            i += n
        i += 1
    return out


def inline(t):
    t = html.escape(t, quote=False)
    for lab in LABELS:
        if t.startswith(lab + ":"):
            return f"<strong>{lab}:</strong>" + t[len(lab) + 1:]
    return t


def render(blocks):
    """Nest the content: each h2 opens a section, each h3 a sub-section inside it, and the content sits in an indented body."""
    used, out, toc = set(), [], []
    state = {"sec": False, "sub": False, "ev": False}

    def close_sub():
        if state["sub"]:
            out.append("</div></div>"); state["sub"] = False

    def close_sec():
        close_sub()
        if state["sec"]:
            out.append("</div></section>"); state["sec"] = False

    for k, v in blocks:
        if k == "h2":
            close_sec()
            sid = slug(v, used); toc.append((sid, v))
            out.append(f'<section class="g-sec"><h2 id="{sid}">{esc(v)}</h2><div class="g-body">'); state["sec"] = True
        elif k == "h3":
            close_sub()
            sid = slug(v, used)
            alt = f' <a class="g-alt" href="/{guide.path(BY_NAME[v])}">Alternatives</a>' if v in BY_NAME else ""
            out.append(f'<div class="g-sub"><h3 id="{sid}">{esc(v)}{alt}</h3><div class="g-body">'); state["sub"] = True; state["ev"] = True
        elif k == "list":
            out.append("<ul>" + "".join(f"<li>{inline(x)}</li>" for x in v) + "</ul>")
        elif k == "table":
            head, body = rows_split(v)
            th = "".join(f"<th>{icon('Price') + ' ' if c.startswith('Price') else ''}{esc(c)}</th>" for c in head)
            tr = "".join("<tr>" + "".join(f"<td>{esc(c)}</td>" for c in r) + "</tr>" for r in body)
            out.append(f'<div class="scroll" style="max-height:none"><table class="small-table" style="min-width:640px"><thead><tr>{th}</tr></thead><tbody>{tr}</tbody></table></div>')
        else:
            labelled = any(v.startswith(lab + ":") for lab in LABELS)
            if state["sub"] and state["ev"] and not labelled:
                out.append(f'<p class="g-ev">{ev_html(v)}</p>')
            else:
                state["ev"] = False
                out.append(f"<p>{inline(v)}</p>")
    close_sec()
    return "\n    ".join(out), toc


def rows_split(rows):
    return rows[0], rows[1:]


GUIDE_CSS = """
.g-sec { margin-top:44px; }
.g-sec > h2 { font-size:24px; margin:0 0 14px; padding:10px 14px; background:var(--red-light); border-left:5px solid var(--red); border-radius:0 10px 10px 0; }
.g-body { margin-left:22px; padding-left:18px; border-left:2px solid var(--divider); }
.g-sub { margin:26px 0 0; }
.g-sub > h3 { font-size:18px; margin:0 0 8px; color:var(--red-dark); display:flex; align-items:baseline; gap:12px; flex-wrap:wrap; }
.g-sub > h3::before { content:""; width:9px; height:9px; border-radius:50%; background:var(--red); flex:none; align-self:center; margin-left:-24px; margin-right:-2px; }
.g-sub > .g-body { margin-left:14px; border-left-color:#e6c9c9; }
.g-body p, .g-body li { font-size:14px; line-height:1.6; }
.g-sub .g-body p, .g-sub .g-body li { font-size:13.5px; }
.g-ev { font-size:12.5px !important; color:var(--muted); background:#fff; border:1px solid var(--divider); border-radius:8px; padding:7px 10px; line-height:1.9 !important; }
.pi { display:inline-flex; vertical-align:-3px; margin-right:3px; }
.g-sec .small-table th, .g-sec .small-table td { font-size:12.5px; }
.g-alt { font-size:12.5px; font-weight:600; padding:2px 10px; border:1px solid var(--divider); border-radius:999px; text-decoration:none; background:#fff; }
.g-alt:hover { background:var(--red-light); }
@media (max-width:600px) { .g-body { margin-left:6px; padding-left:12px; } .g-sub > .g-body { margin-left:4px; } .g-sub > h3::before { margin-left:-18px; } }
"""


def build():
    text = open(SRC).read().replace("{TF_SCORE}", str(site_compare.score(site_compare.TF_ROW)[0]))
    body, toc = render(parse(text))
    nav = "".join(f'<li><a href="#{s}">{esc(t)}</a></li>' for s, t in toc)
    page_body = f'''    <h1>{esc(GUIDE_TITLE)}</h1>
    <p class="meta">Last checked {site_compare.CHECKED_NEW} · Google Play, App Store, G2, Capterra and Trustpilot</p>
    <p class="legend">On this page</p>
    <ul class="legend">{nav}</ul>
    <p class="legend">Ratings: {icon("Play")} Google Play · {icon("iPhone")} Apple App Store · {icon("G2")} G2 · {icon("Capterra")} Capterra · {icon("Trustpilot")} Trustpilot · {icon("Price")} price per user per month</p>
    {body}
    <p>For a deeper look at field force automation apps alone, see <a href="/{TOP_PATH}">{esc(site_compare.TOP_TITLE)}</a>.</p>'''
    desc = "Four categories and 36 field tracking apps compared on ratings, reviews, price and fit: field force automation, sales force automation, field service management and HR tools."
    w(GUIDE_PATH, page(GUIDE_TITLE, desc, GUIDE_PATH, page_body, guide.jsonld_guide(GUIDE_TITLE, GUIDE_PATH), extra_css=GUIDE_CSS))
