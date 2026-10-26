PAGE_CSS = """
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
:root { --red:#8B1A1A; --red-dark:#5C0F0F; --red-light:#fbeaea; --gold:#F5A623; --text:#1A0A0A; --muted:#6B5050;
  --surface:#fff; --bg:#F9F7F7; --divider:#EDE0E0; }
html { scroll-behavior: smooth; }
body { font-family:'Sora',-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; background:var(--bg); color:var(--text); line-height:1.65; -webkit-font-smoothing:antialiased; }
header { background:var(--red); padding:14px 20px; }
header a { color:#fff; text-decoration:none; font-weight:700; display:flex; align-items:center; gap:10px; max-width:1100px; margin:0 auto; }
header img { width:34px; height:34px; border-radius:8px; }
main { max-width:1100px; margin:0 auto; padding:28px 20px 56px; }
h1 { font-size:clamp(26px,5vw,36px); line-height:1.2; font-weight:800; margin-bottom:10px; }
h2 { font-size:22px; margin:40px 0 10px; color:var(--red-dark); }
h3 { font-size:16px; margin:20px 0 6px; }
p, li { font-size:15px; color:#3a2a2a; max-width:780px; }
p { margin-bottom:12px; }
ul, ol { margin:0 0 12px 22px; }
a { color:var(--red); }
.meta { font-size:13px; color:var(--muted); margin-bottom:18px; }
.muted { color:var(--muted); font-size:13px; }
.crumbs { font-size:13px; margin-bottom:12px; }
.hero-img { display:block; width:100%; max-width:780px; height:auto; border-radius:14px; border:1px solid var(--divider); margin:4px 0 20px; }
.factors { display:grid; grid-template-columns:repeat(3,1fr); gap:14px; margin:14px 0; }
.factor { background:var(--surface); border:1px solid var(--divider); border-radius:12px; padding:4px 18px 8px; }
.factor p { max-width:none; }
.num { display:inline-block; background:var(--red); color:#fff; border-radius:50%; width:24px; height:24px; line-height:24px; text-align:center; font-size:13px; margin-right:8px; }
@media (max-width:900px){ .factors{grid-template-columns:repeat(2,1fr);} }
@media (max-width:560px){ .factors{grid-template-columns:1fr;} }
.scroll { overflow-x:auto; margin:14px 0 6px; border:1px solid var(--divider); border-radius:10px; background:var(--surface); max-height:80vh; }
table { border-collapse:separate; border-spacing:0; width:100%; min-width:2000px; font-size:12.5px; }
th, td { padding:8px 9px; text-align:left; vertical-align:top; border-bottom:1px solid var(--divider); border-right:1px solid var(--divider); }
thead th { background:#f3ecec; position:sticky; top:0; z-index:2; }
tbody th { background:#faf6f6; font-weight:600; position:sticky; left:0; z-index:1; min-width:150px; }
thead th:first-child { left:0; z-index:3; }
tr.tf th, tr.tf td { box-shadow: inset 0 2px 0 var(--red), inset 0 -2px 0 var(--red); }
td.g { background:#e4f4e8; color:#14532d; } td.o { background:#fdf0d5; color:#7a4b00; }
td.r { background:#fbe3e3; color:#7f1d1d; } td.n { background:#efeaea; color:#6B5050; }
.hub-app { background:var(--surface); border:1px solid var(--divider); border-radius:14px; padding:16px 20px; margin:14px 0; max-width:900px; }
.hub-app h3 { margin:0 0 2px; font-size:18px; color:var(--red-dark); }
.hub-app .ev { font-size:12.5px; color:var(--muted); }
.hub-app ul { margin:6px 0 8px 20px; } .hub-app li { font-size:14px; max-width:none; }
.hub-app .best { background:#f3faf4; border-left:4px solid #2e7d32; border-radius:8px; padding:8px 12px; font-size:14px; max-width:none; }
.alt { background:var(--surface); border:1px solid var(--divider); border-left:4px solid #2e7d32; border-radius:12px; padding:14px 18px; margin:10px 0; max-width:860px; }
.alt h3 { margin:0 0 2px; } .alt .ev { font-size:12.5px; color:var(--muted); margin-bottom:4px; } .alt p { margin:0 0 6px; }
.summary-table { min-width:1000px; } .summary-table ul { margin:0 0 0 18px; } .summary-table li { font-size:12.5px; max-width:none; margin-bottom:2px; }
.hub-app .best ul { margin:4px 0 6px 20px; } .summary-table td { vertical-align:top; background:#fff; }
.score { display:block; font-weight:700; font-size:11.5px; color:var(--red-dark); margin-top:2px; }
.legend { font-size:12.5px; color:var(--muted); max-width:900px; }
.small-table { min-width:520px; }
.pick { background:var(--surface); border:1px solid var(--divider); border-radius:10px; padding:12px 16px; margin:8px 0; max-width:780px; }
.issue { background:var(--surface); border:1px solid var(--divider); border-radius:12px; padding:14px 18px; margin:10px 0; max-width:820px; }
.issue h3 { margin:0 0 2px; color:var(--red-dark); } .issue p { margin:0; }
.issue .ev { font-size:12.5px; color:var(--muted); margin-bottom:4px; }
.fix-grid { display:grid; grid-template-columns:repeat(2,1fr); gap:12px; margin:12px 0; }
.fix { background:var(--surface); border:1.5px solid var(--divider); border-left:4px solid var(--red); border-radius:12px; padding:12px 16px; }
.fix h3 { margin:0 0 4px; font-size:15px; } .fix p { margin:0; font-size:14px; }
@media (max-width:640px){ .fix-grid{grid-template-columns:1fr;} }
ol.ranked li { margin-bottom:4px; max-width:none; }
.cta { background:var(--surface); border:1.5px solid var(--gold); border-radius:14px; padding:16px 20px; margin:26px 0; max-width:820px; }
.cta a.btn { display:inline-block; background:var(--red); color:#fff; padding:9px 18px; border-radius:10px; text-decoration:none; font-weight:700; margin-top:6px; }
/* chart */
.chart-scroll { overflow-x:auto; } .chart-scroll svg { display:block; min-width:560px; width:100%; height:auto; }
.chart-wrap { position:relative; }
.chart-tip { position:absolute; pointer-events:none; display:none; z-index:2; background:var(--surface); border:1px solid var(--divider); border-radius:10px; box-shadow:0 4px 18px rgba(0,0,0,.12); padding:8px 10px; font-size:12px; min-width:170px; }
.chart-tip .tip-head { color:var(--muted); font-size:11px; margin-bottom:4px; }
.chart-tip .tip-row { display:flex; align-items:center; gap:6px; line-height:1.7; }
.chart-tip .tip-key { width:12px; height:0; border-top:3px solid; flex-shrink:0; }
.chart-tip .tip-val { font-weight:700; margin-left:auto; padding-left:10px; } .chart-tip .tip-name { color:var(--muted); }
.chart-legend { display:flex; flex-wrap:wrap; gap:6px 16px; font-size:12px; color:var(--muted); margin-top:8px; }
.chart-legend span { display:inline-flex; align-items:center; gap:6px; }
.chart-legend i { display:inline-block; width:16px; height:0; border-top:3px solid; }
.viz-note { font-size:12px; color:var(--muted); line-height:1.5; margin:10px 0 0; max-width:none; }
.pricing-table-scroll { overflow-x:auto; border:1.5px solid var(--divider); border-radius:14px; background:var(--surface); margin-top:10px; }
.pricing-table { border-collapse:collapse; width:100%; min-width:900px; font-size:12px; }
.pricing-table th, .pricing-table td { padding:9px 10px; text-align:right; border-bottom:1px solid var(--divider); border-right:none; position:static; }
.pricing-table th:first-child, .pricing-table td:first-child { text-align:left; font-weight:600; }
.pricing-table thead th { background:#f3ecec; font-weight:700; vertical-align:bottom; }
.pricing-table .us { background:#fffaf0; font-weight:700; color:var(--red-dark); }
.pricing-note { font-size:11px; color:var(--muted); line-height:1.5; margin-top:8px; max-width:none; }
details { margin-top:12px; font-size:13px; } summary { cursor:pointer; font-weight:600; color:var(--red); }
footer { text-align:center; font-size:13px; color:var(--muted); padding:28px 20px; border-top:1px solid var(--divider); }
"""

LANDING_CSS = """    .claim-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-top: 14px; }
    .claim { background: var(--surface); border: 1.5px solid var(--divider); border-left: 4px solid var(--red); border-radius: 14px; padding: 14px 16px; }
    .claim h3 { font-size: 14px; font-weight: 700; color: var(--red-dark); margin-bottom: 4px; }
    .claim p { font-size: 12.5px; color: var(--muted); line-height: 1.6; }
    @media (max-width: 800px) { .claim-grid { grid-template-columns: 1fr 1fr; } }
    @media (max-width: 520px) { .claim-grid { grid-template-columns: 1fr; } }
"""

ENTERPRISE = """      <!-- Enterprise -->
      <div class="pricing-card enterprise">
        <div class="pricing-badge badge-enterprise">Enterprise</div>
        <div class="pricing-seats">100+ <span>users</span></div>
        <div class="pricing-price">$399 per year</div>
        <hr class="pricing-divider"/>
        <div class="pricing-perks">
          <div class="perk"><div class="perk-dot red">✓</div>The usage cost stays at $399 a year, however large your team gets.</div>
          <div class="perk"><div class="perk-dot red">✓</div>One-time cost: data localisation, so your data is stored in the region you choose.</div>
          <div class="perk"><div class="perk-dot red">✓</div>One-time cost: on-premise hosting or your own cloud setup.</div>
          <div class="perk"><div class="perk-dot red">✓</div>One-time cost: custom features, API integrations and business-specific workflows.</div>
          <div class="perk"><div class="perk-dot red">✓</div>Full feature access. Priority support.</div>
        </div>
        <div class="pricing-cond">
          <strong>Get a quote for the one-time items:</strong> email <a href="mailto:developer@shristigroup.com" style="color:var(--red);font-weight:600;text-decoration:none;">developer@shristigroup.com</a> with your requirements.
        </div>
      </div>
"""
