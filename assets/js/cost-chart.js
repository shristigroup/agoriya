// Price-per-year line chart. Reads <script type="application/json" id="cost-data"> and draws into #cost-chart.
// Optional data-highlight="key1,key2" on #cost-chart emphasises those series and mutes the rest (TrackFolks stays bold).
(function () {
  var host = document.getElementById('cost-chart');
  var raw = document.getElementById('cost-data');
  if (!host || !raw) return;
  var data = JSON.parse(raw.textContent);
  var users = data.users, series = data.series, YMAX = data.ymax || 2400;
  var LOG = data.scale === 'log', YMIN = data.ymin || 1, TICKS = data.ticks || null;
  var hl = (host.getAttribute('data-highlight') || '').split(',').filter(Boolean);
  function isOn(s) { return !hl.length || s.key === 'trackfolks' || hl.indexOf(s.key) > -1; }
  var last = users.length - 1;
  function offScale(s) { return s.v[last] > YMAX; }
  var rows = series.filter(offScale).length;
  var W = 700, L = 58, R = 200, T = 22 + rows * 17, B = 46, H = T + (LOG ? 380 : 280) + B;
  var pw = W - L - R, ph = H - T - B;
  var NS = 'http://www.w3.org/2000/svg';
  function el(tag, attrs, text) {
    var e = document.createElementNS(NS, tag);
    for (var k in attrs) e.setAttribute(k, attrs[k]);
    if (text != null) e.textContent = text;
    return e;
  }
  function X(u) { return L + (u - users[0]) / (users[last] - users[0]) * pw; }
  function Y(v) {
    if (LOG) { var vv = Math.max(v, YMIN); return T + ph - (Math.log(vv) - Math.log(YMIN)) / (Math.log(YMAX) - Math.log(YMIN)) * ph; }
    return T + ph - v / YMAX * ph;
  }
  function money(v) { return '$' + v.toLocaleString('en-US'); }

  var svg = el('svg', { viewBox: '0 0 ' + W + ' ' + H, role: 'img',
    'aria-label': 'Line chart, on a logarithmic scale, of price per year in US dollars against number of users. TrackFolks is capped at $499 a year. The same numbers are in the table below the chart.' });
  var clip = el('clipPath', { id: 'plot-clip' });
  clip.appendChild(el('rect', { x: L - 4, y: T, width: pw + 8, height: ph }));
  var defs = el('defs', {}); defs.appendChild(clip); svg.appendChild(defs);
  var ticks = TICKS || [0, 1, 2, 3, 4].map(function (g) { return g * YMAX / 4; });
  ticks.forEach(function (t) {
    svg.appendChild(el('line', { x1: L, x2: L + pw, y1: Y(t), y2: Y(t), stroke: '#EDE0E0', 'stroke-width': 1 }));
    svg.appendChild(el('text', { x: L - 8, y: Y(t) + 4, 'text-anchor': 'end', 'font-size': 11, fill: '#6B5050' }, money(t)));
  });
  if (LOG) {
    svg.appendChild(el('line', { x1: L, x2: L + pw, y1: T + ph, y2: T + ph, stroke: '#B09090', 'stroke-width': 1 }));
    svg.appendChild(el('text', { x: L - 8, y: T + ph + 4, 'text-anchor': 'end', 'font-size': 11, fill: '#6B5050' }, '$0'));
  }
  users.forEach(function (u) { svg.appendChild(el('text', { x: X(u), y: T + ph + 18, 'text-anchor': 'middle', 'font-size': 11, fill: '#6B5050' }, String(u))); });
  svg.appendChild(el('text', { x: L + pw / 2, y: H - 6, 'text-anchor': 'middle', 'font-size': 11, fill: '#6B5050' }, 'Number of users'));
  svg.appendChild(el('text', { transform: 'translate(13,' + (T + ph / 2) + ') rotate(-90)', 'text-anchor': 'middle', 'font-size': 11, fill: '#6B5050' }, 'Price per year (USD)'));

  var lines = el('g', { 'clip-path': 'url(#plot-clip)' });
  series.slice().reverse().forEach(function (s) {
    var d = s.v.map(function (v, i) { return (i ? 'L' : 'M') + X(users[i]).toFixed(1) + ' ' + Y(v).toFixed(1); }).join(' ');
    var a = { d: d, fill: 'none', stroke: s.color, 'stroke-width': isOn(s) ? s.w : 1.5, 'stroke-linejoin': 'round', 'stroke-linecap': 'round', opacity: isOn(s) ? 1 : 0.3 };
    if (s.dash) a['stroke-dasharray'] = s.dash;
    lines.appendChild(el('path', a));
  });
  svg.appendChild(lines);

  // Lines that leave the top of the chart: a labelled arrow on the top edge, where the line exits.
  var row = 0;
  series.filter(offScale).sort(function (a, b) { return b.v[0] - a.v[0]; }).forEach(function (s) {
    var ux = users[0];
    for (var i = 1; i < users.length; i++) {
      if (s.v[i - 1] <= YMAX && s.v[i] > YMAX) { ux = users[i - 1] + (YMAX - s.v[i - 1]) / (s.v[i] - s.v[i - 1]) * (users[i] - users[i - 1]); break; }
    }
    var x = X(ux), y = T - 6 - row * 17;
    svg.appendChild(el('line', { x1: x, x2: x, y1: T, y2: y + 3, stroke: s.color, 'stroke-width': 1.5, opacity: isOn(s) ? 1 : 0.4 }));
    svg.appendChild(el('text', { x: x + 6, y: y, 'font-size': 11, fill: '#1A0A0A', opacity: isOn(s) ? 1 : 0.55 }, '↑ ' + s.name + ' ' + money(s.v[last]) + ' at ' + users[last] + ' users'));
    row++;
  });

  // Right-end labels for lines still on the chart, nudged apart.
  var labels = series.filter(function (s) { return !offScale(s); }).map(function (s) { return { s: s, y: Y(s.v[last]) }; }).sort(function (a, b) { return a.y - b.y; });
  for (var i = 1; i < labels.length; i++) if (labels[i].y - labels[i - 1].y < 15) labels[i].y = labels[i - 1].y + 15;
  labels.forEach(function (l) {
    var on = isOn(l.s);
    svg.appendChild(el('line', { x1: L + pw + 6, x2: L + pw + 20, y1: l.y, y2: l.y, stroke: l.s.color, 'stroke-width': 3, 'stroke-dasharray': l.s.dash, opacity: on ? 1 : 0.35 }));
    svg.appendChild(el('text', { x: L + pw + 26, y: l.y + 4, 'font-size': 12, fill: '#1A0A0A', opacity: on ? 1 : 0.55, 'font-weight': l.s.key === 'trackfolks' ? 700 : 400 }, l.s.name + ' ' + money(l.s.v[last])));
  });

  var guide = el('line', { y1: T, y2: T + ph, stroke: '#6B5050', 'stroke-width': 1, 'stroke-dasharray': '3 3', visibility: 'hidden' });
  var dots = series.map(function (s) { return el('circle', { r: 5, fill: s.color, stroke: '#fff', 'stroke-width': 2, visibility: 'hidden' }); });
  svg.appendChild(guide); dots.forEach(function (c) { svg.appendChild(c); });
  var hit = el('rect', { x: L - 10, y: T, width: pw + 20, height: ph, fill: 'transparent', tabindex: 0, 'aria-label': 'Chart values. Use left and right arrow keys to move between team sizes.' });
  svg.appendChild(hit);

  var tip = document.createElement('div'); tip.className = 'chart-tip';
  var wrap = document.createElement('div'); wrap.className = 'chart-wrap';
  var scroll = document.createElement('div'); scroll.className = 'chart-scroll';
  scroll.appendChild(svg); wrap.appendChild(scroll); wrap.appendChild(tip); host.appendChild(wrap);

  var legend = document.createElement('div'); legend.className = 'chart-legend';
  series.forEach(function (s) {
    var item = document.createElement('span'), key = document.createElement('i');
    key.style.borderColor = s.color; if (s.dash) key.style.borderTopStyle = 'dashed';
    item.appendChild(key); item.appendChild(document.createTextNode(s.name)); legend.appendChild(item);
  });
  host.appendChild(legend);

  function show(idx) {
    var x = X(users[idx]);
    guide.setAttribute('x1', x); guide.setAttribute('x2', x); guide.setAttribute('visibility', 'visible');
    series.forEach(function (s, i) {
      dots[i].setAttribute('cx', x); dots[i].setAttribute('cy', Y(s.v[idx]));
      dots[i].setAttribute('visibility', s.v[idx] <= YMAX && isOn(s) ? 'visible' : 'hidden');
    });
    tip.textContent = '';
    var head = document.createElement('div'); head.className = 'tip-head'; head.textContent = users[idx] + ' users, per year'; tip.appendChild(head);
    series.map(function (s) { return { s: s, v: s.v[idx] }; }).sort(function (a, b) { return b.v - a.v; }).forEach(function (r) {
      var rw = document.createElement('div'); rw.className = 'tip-row';
      var key = document.createElement('span'); key.className = 'tip-key'; key.style.borderTopColor = r.s.color; if (r.s.dash) key.style.borderTopStyle = 'dashed';
      var nm = document.createElement('span'); nm.className = 'tip-name'; nm.textContent = r.s.name;
      var val = document.createElement('span'); val.className = 'tip-val'; val.textContent = money(r.v);
      rw.appendChild(key); rw.appendChild(nm); rw.appendChild(val); tip.appendChild(rw);
    });
    tip.style.display = 'block';
    var box = svg.getBoundingClientRect(), wb = wrap.getBoundingClientRect(), k = box.width / W;
    var left = box.left - wb.left + x * k + 14;
    if (left + tip.offsetWidth > wb.width) left = box.left - wb.left + x * k - tip.offsetWidth - 14;
    tip.style.left = Math.max(0, left) + 'px'; tip.style.top = (box.top - wb.top + T * k) + 'px';
  }
  function hide() { guide.setAttribute('visibility', 'hidden'); dots.forEach(function (c) { c.setAttribute('visibility', 'hidden'); }); tip.style.display = 'none'; }
  var cur = 0;
  function nearest(evt) {
    var box = svg.getBoundingClientRect(), px = (evt.clientX - box.left) / (box.width / W), best = 0;
    users.forEach(function (u, i) { if (Math.abs(X(u) - px) < Math.abs(X(users[best]) - px)) best = i; });
    return best;
  }
  hit.addEventListener('pointermove', function (e) { cur = nearest(e); show(cur); });
  hit.addEventListener('pointerleave', hide);
  hit.addEventListener('focus', function () { show(cur); });
  hit.addEventListener('blur', hide);
  hit.addEventListener('keydown', function (e) {
    if (e.key === 'ArrowRight') { cur = Math.min(last, cur + 1); show(cur); e.preventDefault(); }
    if (e.key === 'ArrowLeft') { cur = Math.max(0, cur - 1); show(cur); e.preventDefault(); }
  });
})();
