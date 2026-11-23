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
    used, out, toc = set(), [], []
    for k, v in blocks:
        if k == "h2":
            sid = slug(v, used); toc.append((sid, v))
            out.append(f'<h2 id="{sid}">{esc(v)}</h2>')
        elif k == "h3":
            sid = slug(v, used)
            alt = f' <a class="muted" style="font-size:13px;font-weight:400" href="/{guide.path(BY_NAME[v])}">Alternatives</a>' if v in BY_NAME else ""
            out.append(f'<h3 id="{sid}">{esc(v)}{alt}</h3>')
        elif k == "list":
            out.append("<ul>" + "".join(f"<li>{inline(x)}</li>" for x in v) + "</ul>")
        elif k == "table":
            head, body = rows_split(v)
            th = "".join(f"<th>{esc(c)}</th>" for c in head)
            tr = "".join("<tr>" + "".join(f"<td>{esc(c)}</td>" for c in r) + "</tr>" for r in body)
            out.append(f'<div class="scroll" style="max-height:none"><table class="small-table" style="min-width:640px"><thead><tr>{th}</tr></thead><tbody>{tr}</tbody></table></div>')
        else:
            out.append(f"<p>{inline(v)}</p>")
    return "\n    ".join(out), toc


def rows_split(rows):
    return rows[0], rows[1:]


def build():
    text = open(SRC).read().replace("{TF_SCORE}", str(site_compare.score(site_compare.TF_ROW)[0]))
    body, toc = render(parse(text))
    nav = "".join(f'<li><a href="#{s}">{esc(t)}</a></li>' for s, t in toc)
    page_body = f'''    <h1>{esc(GUIDE_TITLE)}</h1>
    <p class="meta">Last checked {site_compare.CHECKED_NEW} · Google Play, App Store, G2, Capterra and Trustpilot</p>
    <p class="legend">On this page</p>
    <ul class="legend">{nav}</ul>
    {body}
    <p>For a deeper look at field force automation apps alone, see <a href="/{TOP_PATH}">{esc(site_compare.TOP_TITLE)}</a>.</p>'''
    desc = "Four categories and 36 field tracking apps compared on ratings, reviews, price and fit: field force automation, sales force automation, field service management and HR tools."
    w(GUIDE_PATH, page(GUIDE_TITLE, desc, GUIDE_PATH, page_body, guide.jsonld_guide(GUIDE_TITLE, GUIDE_PATH)))
