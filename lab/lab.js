// Font lab: plain static script, no build step, no network beyond this server.
(async () => {
  const STYLE_NAMES = { regular: "Regular", italic: "Italic", bold: "Bold", bolditalic: "Bold Italic" };
  const data = await (await fetch("fonts.json")).json();
  const fonts = data.fonts;
  const byName = Object.fromEntries(fonts.map(f => [f.name, f]));
  const usable = fonts.filter(f => f.virtual || Object.keys(f.styles).length);
  const $ = id => document.getElementById(id);
  const q = new URLSearchParams(location.search);

  // ---- @font-face for every downloaded style (files only load when a style is used) ----
  const css = [];
  for (const f of fonts) {
    for (const [st, info] of Object.entries(f.styles)) {
      const italic = st.includes("italic");
      let weight = st.startsWith("bold") ? "700" : "400";
      if (info.variable && info.axes && info.axes.wght) weight = `${info.axes.wght[0]} ${info.axes.wght[2]}`;
      css.push(`@font-face{font-family:"lab-${f.name}";src:url("fonts/${f.name}/${st}.woff2") format("woff2");font-weight:${weight};font-style:${italic ? "italic" : "normal"};font-display:block}`);
    }
  }
  const styleEl = document.createElement("style");
  styleEl.textContent = css.join("\n");
  document.head.appendChild(styleEl);

  const ff = name => byName[name].virtual ? byName[name].family : `"lab-${name}", "lab-fallback"`;
  const ffTitle = name => name === "umschrift" ? `"lab-umschrift", serif` : ff(name);
  const kb = n => `${Math.round(n / 1024)} KB`;

  // ---- what a font can do ----
  function caps(name) {
    const f = byName[name];
    if (f.virtual) return { bold: true, italic: true, bolditalic: true, max: 900, label: "platform serif (Times on macOS Chrome)" };
    const max = f.weightRange ? f.weightRange[1] : (f.hasBold ? 700 : 400);
    const parts = Object.keys(f.styles).map(s => STYLE_NAMES[s]);
    if (f.weightRange) parts.push(`variable wght ${f.weightRange[0]}-${f.weightRange[1]}`);
    return { bold: f.hasBold, italic: f.hasItalic, bolditalic: f.hasBoldItalic, max, label: parts.join(", ") };
  }
  const score = f => f.virtual ? "?" : `${f.styles.regular ? f.styles.regular.coreScore : 0}/22`;

  // ---- pickers ----
  function fill(sel, list, withTodayLabel) {
    for (const f of list) {
      const o = document.createElement("option");
      o.value = f.name;
      o.textContent = `${f.family}${f.control ? " (sans control)" : ""}  [${score(f)}]${f.today ? "  (today)" : ""}`;
      sel.appendChild(o);
    }
  }
  const titleList = usable.filter(f => !f.virtual);
  const quoteList = usable;
  fill($("title-font"), titleList);
  fill($("quote-font"), quoteList);
  fill($("spec-font"), titleList);

  const state = {
    title: q.get("title") || "gentium", tw: q.get("tw") || "700", ti: q.get("ti") === "1",
    quote: q.get("quote") || "gentium", qw: q.get("qw") || "900", qi: q.get("qi") === "1",
    width: q.get("width") || "765", side: q.get("side") === "1",
    spec: q.get("spec") || q.get("title") || "gentium", view: q.get("view") || "card",
  };

  function weightOptions(sel, name, current) {
    const c = caps(name), f = byName[name];
    sel.innerHTML = "";
    const opts = [["400", "Regular 400", true]];
    opts.push(["700", "Bold 700", c.bold]);
    opts.push(["900", f.virtual || (f.weightRange && f.weightRange[1] >= 900) ? "Heavy 900 (today's quote)" : "900 (uses Bold 700 if present)", c.bold]);
    for (const [v, t, ok] of opts) {
      const o = document.createElement("option");
      o.value = v; o.textContent = t + (ok ? "" : " (not in font)"); o.disabled = !ok;
      sel.appendChild(o);
    }
    sel.value = [...sel.options].find(o => o.value === current && !o.disabled) ? current : "400";
    return sel.value;
  }

  function status(el, name, w, italic) {
    const c = caps(name), msgs = [], f = byName[name];
    el.className = "status";
    msgs.push(c.label);
    if (!f.virtual && f.styles.regular) msgs.push(`core ${f.styles.regular.coreScore}/22 regular`);
    if (italic && !c.italic) { msgs.push("NO italic: shows upright"); el.classList.add("warn"); }
    else if (italic && +w >= 700 && !c.bolditalic) { msgs.push("no Bold Italic face: nearest real face"); el.classList.add("warn"); }
    el.textContent = msgs.join("; ");
  }

  function applyCard() {
    const root = $("view-card");
    const tf = state.title, qf = state.quote;
    state.tw = weightOptions($("title-weight"), tf, state.tw);
    state.qw = weightOptions($("quote-weight"), qf, state.qw);
    $("title-italic").disabled = !caps(tf).italic;
    $("quote-italic").disabled = !caps(qf).italic;
    const cand = $("cand");
    cand.style.setProperty("--title-ff", ffTitle(tf));
    cand.style.setProperty("--title-w", state.tw);
    cand.style.setProperty("--title-s", state.ti ? "italic" : "normal");
    cand.style.setProperty("--quote-ff", ff(qf));
    cand.style.setProperty("--quote-w", state.qw);
    cand.style.setProperty("--quote-s", state.qi ? "italic" : "normal");
    // real Unicode for candidates, keyboard-encoded for Umschrift
    cand.querySelector(".t1").textContent = tf === "umschrift" ? "Ink Ok#" : "Ink Ḥkꜣ";
    cand.querySelector(".t2").textContent = tf === "umschrift" ? "{.Órg}" : "{.org}";
    $("cand-cap").textContent = `Candidate: title ${byName[tf].family}, quote ${byName[qf].family}`;
    status($("title-status"), tf, state.tw, state.ti);
    status($("quote-status"), qf, state.qw, state.qi);
    for (const w of document.querySelectorAll(".cardwrap")) w.style.setProperty("--cw", state.width + "px");
    $("stage").classList.toggle("side", state.side);
  }

  // ---- specimen ----
  function glyphText(label) {
    const m = /U\+([0-9A-F]{4})$/.exec(label);
    if (!m) return label;
    const base = m[1] === "0331" ? "H" : "i";
    return base + String.fromCodePoint(parseInt(m[1], 16));
  }
  function codeOf(label) {
    const m = /U\+([0-9A-F]{4})$/.exec(label);
    if (m) return (m[1] === "0331" ? "H+" : "i+") + m[1];
    return [...label].map(c => c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")).map(h => "U+" + h).join(" ");
  }
  function specimenRows(f) {
    const rows = [];
    const v = f.weightRange;
    for (const st of Object.keys(f.styles)) {
      const italic = st.includes("italic");
      if (v) {
        rows.push({ name: `${STYLE_NAMES[st]} (variable, weight 400)`, st, w: 400, italic });
        if (v[1] >= 700) rows.push({ name: `${STYLE_NAMES[st]} (variable, weight 700 = bold${italic ? " italic" : ""})`, st: st, w: 700, italic, key: italic ? "bolditalic" : "bold" });
      } else rows.push({ name: STYLE_NAMES[st], st, w: st.startsWith("bold") ? 700 : 400, italic });
    }
    return rows;
  }
  function renderSpecimen() {
    const f = byName[state.spec], el = $("specimen");
    const tag = f.styles.regular;
    let html = `<h2 class="spec-head">${f.family} <small>${f.licence}${tag ? "; core " + tag.coreScore + "/22 regular; " + (tag.gposMarkFeature ? "has GPOS mark positioning" : "NO GPOS mark feature") : ""}</small></h2>`;
    html += `<p class="legend">Red box = missing in the cmap (fonts.json, the truth). Blue-tinted cells are extras (Q q and the yod marks). The fallback is a monospace face, so a missing glyph also looks different. Combining marks are shown on H or i. Cardinal rule: cmap says present, the glyph can still be badly placed, so look.</p>`;
    for (const r of specimenRows(f)) {
      const key = r.key || r.st;
      const info = f.styles[r.st];
      const cov = f.styles[key] || info;
      const style = `font-family:'lab-${f.name}','lab-fallback';font-weight:${r.w};font-style:${r.italic ? "italic" : "normal"}`;
      const cell = (label, ok, extra) => `<div class="glyph${ok ? "" : " miss"}${extra ? " extra" : ""}"><div class="g">${glyphText(label)}</div><div class="u">${codeOf(label)}</div></div>`;
      html += `<div class="spec-style" style="${style}"><h3 style="font-family:system-ui;font-weight:600;font-style:normal">${r.name} - core ${cov.coreScore}/22, ${kb(cov.woff2Bytes)} woff2</h3><div class="glyphs">`;
      for (const [label, ok] of Object.entries(cov.core)) html += cell(label, ok, false);
      for (const [label, ok] of Object.entries(cov.extra)) html += cell(label, ok, true);
      html += `</div><div class="samples"><div class="t">Ink Ḥkꜣ {.org}  Ꜣꜣ Ꜥꜥ ḤḥḪḫẖH̱ Šš ṮṯḎḏ ṬṭḲḳ Qq Ꞽꞽ ꞽ̓ ꞽ͗</div><div class="q">“May your words occur; may your magic shine.”</div><div class="c">— Ritner 1993, p. 30; Hornung &amp; Abt 2007, p. 152</div></div></div>`;
    }
    el.innerHTML = html;
  }

  // ---- table ----
  function renderTable() {
    const sorted = [...fonts].sort((a, b) => (b.coreRegular || -1) - (a.coreRegular || -1));
    let h = `<h2>All candidates</h2><p class="legend">Core = the 22 core characters (${data.coreDefinition.replace(/^22 core chars: /, "")}). Counts per style: R / I / B / BI. Extra = Q q + U+0313 + U+0357 present in Regular (of 4). Sizes are woff2 per style. A red licence cell = unclear web terms.</p>`;
    h += `<table><tr><th>Font</th><th>Core R / I / B / BI</th><th>Extra (reg)</th><th>Basic Latin</th><th>Mark GPOS</th><th>Styles</th><th>woff2 sizes</th><th>Licence</th><th>Source</th><th>Use</th></tr>`;
    for (const f of sorted) {
      const ss = f.styles;
      if (f.virtual) { h += `<tr><td>${f.family} (system serif)</td><td colspan="7">${f.notes}</td><td></td><td><button data-q="${f.name}">quote</button></td></tr>`; continue; }
      if (!Object.keys(ss).length) { h += `<tr class="fail flag"><td>${f.family}</td><td colspan="5">not downloaded: ${f.unavailable || "missing"}</td><td></td><td class="lic">${f.licence}</td><td><a href="${f.source}" target="_blank" rel="noreferrer">${f.source}</a></td><td></td></tr>`; continue; }
      const c = k => ss[k] ? `<span class="${ss[k].coreScore === 22 ? "ok" : "bad"}">${ss[k].coreScore}</span>` : "-";
      const r = ss.regular;
      const ext = r ? Object.values(r.extra).filter(Boolean).length : "-";
      const sizes = Object.entries(ss).map(([k, v]) => `${STYLE_NAMES[k]} ${kb(v.woff2Bytes)}`).join("<br>");
      const flag = f.webLicenceUnclear;
      h += `<tr class="${flag ? "flag" : ""}"><td><b>${f.family}</b>${f.control ? " (sans control)" : ""}${f.today ? " (today)" : ""}<br><small>${f.notes}</small></td><td class="num">${c("regular")} / ${c("italic")} / ${c("bold")} / ${c("bolditalic")}${f.weightRange ? "<br><small>variable: bold from the axis</small>" : ""}</td><td class="num">${ext}/4</td><td>${r && r.basicLatin ? '<span class="ok">yes</span>' : '<span class="bad">no</span>'}</td><td>${r ? (r.gposMarkFeature ? "yes" : "no") : ""}</td><td>${caps(f.name).label}</td><td>${sizes}</td><td class="lic">${f.licence}</td><td>${f.source ? `<a href="${f.source}" target="_blank" rel="noreferrer">source</a>` : ""}</td><td><button data-t="${f.name}">title</button><button data-q="${f.name}">quote</button><button data-s="${f.name}">specimen</button></td></tr>`;
    }
    h += `</table>`;
    $("table").innerHTML = h;
  }

  // ---- wiring ----
  function sync() {
    const p = new URLSearchParams({ title: state.title, tw: state.tw, ti: +state.ti, quote: state.quote, qw: state.qw, qi: +state.qi, width: state.width, side: +state.side, spec: state.spec, view: state.view });
    history.replaceState(null, "", "?" + p);
  }
  function showView() {
    for (const v of ["card", "specimen", "table"]) $("view-" + v).classList.toggle("on", v === state.view);
    for (const b of document.querySelectorAll("#views button")) b.classList.toggle("on", b.dataset.view === state.view);
    if (state.view === "specimen") renderSpecimen();
  }
  function setAll() {
    $("title-font").value = state.title; $("quote-font").value = state.quote; $("spec-font").value = state.spec;
    $("title-italic").checked = state.ti; $("quote-italic").checked = state.qi;
    $("card-width").value = state.width; $("side").checked = state.side;
    applyCard(); showView(); sync();
  }
  $("title-font").onchange = e => { state.title = e.target.value; setAll(); };
  $("quote-font").onchange = e => { state.quote = e.target.value; setAll(); };
  $("spec-font").onchange = e => { state.spec = e.target.value; setAll(); };
  $("title-weight").onchange = e => { state.tw = e.target.value; setAll(); };
  $("quote-weight").onchange = e => { state.qw = e.target.value; setAll(); };
  $("title-italic").onchange = e => { state.ti = e.target.checked; setAll(); };
  $("quote-italic").onchange = e => { state.qi = e.target.checked; setAll(); };
  $("card-width").onchange = e => { state.width = e.target.value; setAll(); };
  $("side").onchange = e => { state.side = e.target.checked; setAll(); };
  for (const b of document.querySelectorAll("#views button")) b.onclick = () => { state.view = b.dataset.view; setAll(); };
  $("table").addEventListener("click", e => {
    const b = e.target.closest("button"); if (!b) return;
    if (b.dataset.t) { state.title = b.dataset.t; state.view = "card"; }
    if (b.dataset.q) { state.quote = b.dataset.q; state.view = "card"; }
    if (b.dataset.s) { state.spec = b.dataset.s; state.view = "specimen"; }
    setAll();
  });

  renderTable();
  setAll();
})();
