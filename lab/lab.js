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
      o.textContent = `${f.family}  [${score(f)}]${f.today ? "  (today)" : ""}`;
      sel.appendChild(o);
    }
  }
  const byFamily = (a, b) => a.family.localeCompare(b.family, undefined, { sensitivity: "base" });
  // today's references first, then the rest A-Z by family name
  const todayFirst = (a, b) => (!!b.today - !!a.today) || byFamily(a, b);
  const titleList = usable.filter(f => !f.virtual).sort(todayFirst);
  const quoteList = [...usable].sort(todayFirst);
  fill($("title-font"), titleList);
  fill($("quote-font"), quoteList);
  fill($("spec-font"), titleList);

  // ---- aleph data (optional: lab/aleph.json from measure-aleph.py) ----
  let aleph = null;
  try { const r = await fetch("aleph.json"); if (r.ok) aleph = await r.json(); } catch (e) { aleph = null; }
  const alephNames = aleph ? aleph.fonts.map(f => f.name) : [];
  const alephDefault = aleph ? aleph.rank_bold.slice(0, 6) : [];

  // ---- state: URL params > localStorage > defaults; every value validated on its own ----
  const STORE_KEY = "inkhk3-lab";
  const DEFAULTS = {
    title: "new-athena-unicode", tw: "700", ti: false, quote: "new-athena-unicode", qw: "900", qi: false, ci: true,
    width: "765", side: false, spec: "new-athena-unicode", view: "card", af: alephDefault, aw: "bold",
    as: "1.18", ay: "0.037",
  };
  const asBool = v => (v === true || v === "1") ? true : (v === false || v === "0") ? false : undefined;
  const oneOf = list => v => list.includes(String(v)) ? String(v) : undefined;
  const fontOk = pred => v => (typeof v === "string" && Object.prototype.hasOwnProperty.call(byName, v) && pred(byName[v])) ? v : undefined;
  const hasFiles = f => !f.virtual && Object.keys(f.styles).length > 0;
  const VALID = {
    title: fontOk(hasFiles), quote: fontOk(f => f.virtual || hasFiles(f)), spec: fontOk(hasFiles),
    tw: oneOf(["400", "700", "900"]), qw: oneOf(["400", "700", "900"]),
    ti: asBool, qi: asBool, ci: asBool, side: asBool,
    width: oneOf(["765", "918", "540", "340"]), view: oneOf(["card", "specimen", "table", "aleph"]),
    aw: oneOf(["bold", "regular"]),
    as: v => { const n = Number(v); return (v !== "" && v !== null && Number.isFinite(n) && n >= 1 && n <= 1.4) ? String(Math.round(n * 100) / 100) : undefined; },
    ay: v => { const n = Number(v); return (v !== "" && v !== null && Number.isFinite(n) && n >= -0.1 && n <= 0.2) ? String(Math.round(n * 1000) / 1000) : undefined; },
    af: v => {
      const arr = Array.isArray(v) ? v : (typeof v === "string" ? v.split(",") : null);
      if (!arr) return undefined;
      const ok = [...new Set(arr.filter(n => typeof n === "string" && alephNames.includes(n)))];
      return (ok.length || !arr.filter(Boolean).length) ? ok : undefined;   // all stale names: back to the default
    },
  };
  const defaults = () => ({ ...DEFAULTS, af: [...DEFAULTS.af] });
  function loadState() {
    const s = defaults(), keys = Object.keys(DEFAULTS);
    let src = null;
    if (keys.some(k => q.has(k))) src = Object.fromEntries(keys.filter(k => q.has(k)).map(k => [k, q.get(k)]));  // URL wins, storage ignored
    else {
      try {
        const o = JSON.parse(localStorage.getItem(STORE_KEY));
        if (o && typeof o === "object" && !Array.isArray(o)) src = o;
      } catch (e) { src = null; }
    }
    let specOk = false;
    if (src) for (const k of keys) {
      try { const v = VALID[k](src[k]); if (v !== undefined) { s[k] = v; if (k === "spec") specOk = true; } } catch (e) { /* keep default */ }
    }
    if (!specOk) s.spec = s.title;
    return s;
  }
  const state = loadState();

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
    $("cite-italic").disabled = !caps(qf).italic;
    const cand = $("cand");
    cand.style.setProperty("--title-ff", ffTitle(tf));
    cand.style.setProperty("--title-w", state.tw);
    cand.style.setProperty("--title-s", state.ti ? "italic" : "normal");
    cand.style.setProperty("--quote-ff", ff(qf));
    cand.style.setProperty("--quote-w", state.qw);
    cand.style.setProperty("--quote-s", state.qi ? "italic" : "normal");
    cand.style.setProperty("--cite-s", state.ci ? "italic" : "normal");
    cand.style.setProperty("--as", tf === "umschrift" ? "1" : state.as);
    cand.style.setProperty("--ay", tf === "umschrift" ? "0" : state.ay);
    // real Unicode for candidates, keyboard-encoded for Umschrift
    cand.querySelector(".t1").innerHTML = tf === "umschrift" ? "Ink Ok#" : 'Ink Ḥk<span class="aleph">ꜣ</span>';
    cand.querySelector(".t2").textContent = tf === "umschrift" ? "{.Órg}" : "{.org}";
    $("cand-cap").textContent = `Candidate: title ${byName[tf].family}, quote ${byName[qf].family}`;
    status($("title-status"), tf, state.tw, state.ti);
    status($("quote-status"), qf, state.qw, state.qi);
    if (state.ci && !caps(qf).italic) { const el = $("quote-status"); el.classList.add("warn"); el.textContent += "; NO italic: citation shows upright"; }
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
    const sorted = [...fonts].sort(byFamily);
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
      h += `<tr class="${flag ? "flag" : ""}"><td><b>${f.family}</b>${f.today ? " (today)" : ""}<br><small>${f.notes}</small></td><td class="num">${c("regular")} / ${c("italic")} / ${c("bold")} / ${c("bolditalic")}${f.weightRange ? "<br><small>variable: bold from the axis</small>" : ""}</td><td class="num">${ext}/4</td><td>${r && r.basicLatin ? '<span class="ok">yes</span>' : '<span class="bad">no</span>'}</td><td>${r ? (r.gposMarkFeature ? "yes" : "no") : ""}</td><td>${caps(f.name).label}</td><td>${sizes}</td><td class="lic">${f.licence}</td><td>${f.source ? `<a href="${f.source}" target="_blank" rel="noreferrer">source</a>` : ""}</td><td><button data-t="${f.name}">title</button><button data-q="${f.name}">quote</button><button data-s="${f.name}">specimen</button></td></tr>`;
    }
    h += `</table>`;
    $("table").innerHTML = h;
  }

  // ---- aleph view ----
  const faceRank = face => aleph["rank_" + face];
  function renderAleph() {
    const el = $("aleph");
    if (!aleph) { el.innerHTML = '<p class="legend">No aleph.json: run lab/measure-aleph.py (see README).</p>'; return; }
    const face = state.aw, U = aleph.umschrift[face];
    const ent = n => aleph.fonts.find(f => f.name === n);
    const order = [...faceRank(face)].sort((a, b) => byFamily(ent(a), ent(b)));   // A-Z; rank stays in the label
    let h = `<div class="abar"><label>Face <select id="aw"><option value="bold">Bold (the title face; Umschrift SB)</option><option value="regular">Regular (Umschrift S)</option></select></label>`;
    h += ` <button data-a="top6">Top 6</button> <button data-a="all">All</button> <button data-a="none">None</button></div><div class="apick">`;
    for (const n of order) {
      const e = ent(n), m = e.faces[face];
      h += `<label class="achk"><input type="checkbox" data-af="${n}"${state.af.includes(n) ? " checked" : ""}> #${m.rank} ${e.family}${face === "bold" && !m.realFace ? " (no bold)" : ""} <small>${m.score.toFixed(2)}</small></label>`;
    }
    h += `</div><p class="legend">Listed A-Z; the rank (#) and score come from aleph-report.md (shape and proportion about equally, formula there). Same font size and baseline in each row: ꜣ in the candidate (left of each pair) against Umschrift's # (right). Guides: baseline (grey), x-height (blue) and cap height (green) of the cell's own font; Umschrift's x-height and cap height are repeated as red dashes inside the candidate cells. Rank is by score, not by eye: look. A face without bold shows its regular.</p>`;
    h += `<div class="acell-key">Umschrift reference (${face === "bold" ? "SB" : "S"}): ꜣ ${U.components} pieces, h/x ${U.hOverX.toFixed(2)}, w/x ${U.wOverX.toFixed(2)}, top/cap ${U.topOverCap.toFixed(2)}</div>`;
    const ufam = `"lab-umschrift", serif`, uw = face === "bold" ? 700 : 400;
    h += tuningBlock();
    const cell = (ff, w, size, text, m, um, extra) => `<div class="acell" style='font-family:${ff};font-weight:${w};font-size:${size}px' data-x="${m.xHeightEm}" data-c="${m.capHeightEm}"${um ? ` data-ux="${um.xHeightEm}" data-uc="${um.capHeightEm}"` : ""}><span class="bl"></span>${text}</div>`;
    for (const n of order) {
      if (!state.af.includes(n)) continue;
      const e = ent(n), m = e.faces[face], f = byName[n];
      const w = face === "bold" && m.realFace ? 700 : 400;
      h += `<div class="arow"><div class="ainfo"><b>${e.family}</b> #${m.rank}, score ${m.score.toFixed(3)} (shape ${m.score_shape.toFixed(2)}, proportion ${m.score_proportion.toFixed(2)}); ꜣ ${m.components} pieces, h/x ${m.hOverX.toFixed(2)}, w/x ${m.wOverX.toFixed(2)}, top/cap ${m.topOverCap.toFixed(2)}; ${f.licence.split(" (")[0]}${face === "bold" && !m.realFace ? "; no bold face, regular shown" : ""}</div><div class="apair">`;
      h += cell(ff(n), w, 96, "Ink Ḥkꜣ", m, U) + cell(ufam, uw, 96, "Ink Ok#", U, null);
      h += cell(ff(n), w, 240, "ꜣ", m, U) + cell(ufam, uw, 240, "#", U, null);
      h += `</div></div>`;
    }
    el.innerHTML = h;
    $("aw").value = face;
    document.fonts.ready.then(() => requestAnimationFrame(placeGuides));
  }
  // ---- the enlarged ꜣ of the title: New Athena Unicode Bold against Umschrift SB, same size and baseline ----
  function tuningBlock() {
    const nau = aleph.fonts.find(f => f.name === "new-athena-unicode"), N = nau && nau.faces.bold, U = aleph.umschrift.bold;
    if (!N) return "";
    const nf = ff("new-athena-unicode"), uf = `"lab-umschrift", serif`;
    const cell = (fam, size, text, m, um) => `<div class="acell" style='font-family:${fam};font-weight:700;font-size:${size}px' data-x="${m.xHeightEm}" data-c="${m.capHeightEm}"${um ? ` data-ux="${um.xHeightEm}" data-uc="${um.capHeightEm}"` : ""}><span class="bl"></span>${text}</div>`;
    let h = `<div class="arow atune" style="--as:${state.as};--ay:${state.ay}"><div class="ainfo"><b>Site title: New Athena Unicode Bold</b> with the enlarged ꜣ (scale ${(+state.as).toFixed(2)}, shift ${(+state.ay).toFixed(3)} em, set in the panel) against Umschrift SB. Left to right: New Athena plain, New Athena with the enlarged ꜣ, Umschrift, then the ꜣ alone (enlarged) against Umschrift's #. Guides as above (grey baseline, blue x-height, green cap height of the cell's font, red dashes = Umschrift's).</div><div class="apair">`;
    h += cell(nf, 96, "Ink Ḥkꜣ", N, U) + cell(nf, 96, 'Ink Ḥk<span class="aleph">ꜣ</span>', N, U) + cell(uf, 96, "Ink Ok#", U, null);
    h += cell(nf, 240, '<span class="aleph">ꜣ</span>', N, U) + cell(uf, 240, "#", U, null);
    h += `</div><div class="ainfo" id="atune-nums"></div></div>`;
    return h;
  }
  // Ink bounds of the glyphs from canvas (measureText of the outline), in em of a 1000 px font.
  const inkCache = {};
  async function ink(fam, ch) {
    const key = fam + ch;
    if (inkCache[key]) return inkCache[key];
    const font = `700 1000px ${fam}`;
    await document.fonts.load(font, ch);
    const c = document.createElement("canvas").getContext("2d");
    c.font = font;
    const t = c.measureText(ch);
    return (inkCache[key] = { top: t.actualBoundingBoxAscent / 1000, bottom: -t.actualBoundingBoxDescent / 1000 });
  }
  async function measureAlephSpan() {
    const nf = `"lab-new-athena-unicode"`, uf = `"lab-umschrift"`;
    const [a, x, H, ua, ux, uE] = await Promise.all([ink(nf, "ꜣ"), ink(nf, "x"), ink(nf, "H"), ink(uf, "#"), ink(uf, "z"), ink(uf, "E")]);
    const s = +state.as, y = +state.ay;
    const top = a.top * s + y, bottom = a.bottom * s + y, h = top - bottom;
    const r = {
      scale: s, shift: y, xHeight: x.top, capHeight: H.top,
      plainHeightX: (a.top - a.bottom) / x.top, plainTopCap: a.top / H.top,
      top, bottom, height: h, heightX: h / x.top, topCap: top / H.top,
      umHeightX: (ua.top - ua.bottom) / ux.top, umTopCap: ua.top / uE.top,
      umTop: ua.top, umBottom: ua.bottom, umX: ux.top, umCap: uE.top,
    };
    window.alephMeasure = r;
    const txt = `ꜣ enlarged: height ${r.height.toFixed(3)} em = ${r.heightX.toFixed(2)} x-heights (Umschrift ${r.umHeightX.toFixed(2)}), top ${r.top.toFixed(3)} em = ${r.topCap.toFixed(2)} cap (Umschrift ${r.umTopCap.toFixed(2)}), bottom ${r.bottom.toFixed(3)} em (Umschrift ${r.umBottom.toFixed(3)}). Plain NAU ꜣ: ${r.plainHeightX.toFixed(2)} x, top ${r.plainTopCap.toFixed(2)} cap.`;
    const el = $("atune-nums"); if (el) el.textContent = txt;
    $("aleph-status").textContent = `${r.heightX.toFixed(2)} x-heights tall (Umschrift ${r.umHeightX.toFixed(2)}); top ${r.topCap.toFixed(2)} cap (Umschrift ${r.umTopCap.toFixed(2)}); bottom ${r.bottom.toFixed(3)} em`;
    return r;
  }
  function placeGuides() {
    for (const c of document.querySelectorAll("#aleph .acell")) {
      c.querySelectorAll(".gl").forEach(n => n.remove());
      const size = parseFloat(getComputedStyle(c).fontSize);
      const base = c.querySelector(".bl").getBoundingClientRect().bottom - c.getBoundingClientRect().top;
      const add = (em, cls) => { const d = document.createElement("i"); d.className = "gl " + cls; d.style.top = (base - em * size) + "px"; c.appendChild(d); };
      add(0, "base"); add(+c.dataset.x, "x"); add(+c.dataset.c, "cap");
      if (c.dataset.ux) { add(+c.dataset.ux, "ux"); add(+c.dataset.uc, "uc"); }
    }
  }
  document.fonts.addEventListener("loadingdone", () => { if (state.view === "aleph") placeGuides(); });

  // ---- persistence ----
  function persist() {
    try {
      const p = new URLSearchParams({ title: state.title, tw: state.tw, ti: +state.ti, quote: state.quote, qw: state.qw, qi: +state.qi, ci: +state.ci, width: state.width, side: +state.side, spec: state.spec, view: state.view, af: state.af.join(","), aw: state.aw, as: state.as, ay: state.ay });
      history.replaceState(null, "", "?" + p);
    } catch (e) { /* e.g. sandboxed URL */ }
    try { localStorage.setItem(STORE_KEY, JSON.stringify(state)); } catch (e) { /* private mode, quota */ }
  }
  function showView() {
    for (const v of ["card", "specimen", "table", "aleph"]) $("view-" + v).classList.toggle("on", v === state.view);
    for (const b of document.querySelectorAll("#views button")) b.classList.toggle("on", b.dataset.view === state.view);
    if (state.view === "specimen") renderSpecimen();
    if (state.view === "aleph") renderAleph();
  }
  function setAll(save = true) {
    $("title-font").value = state.title; $("quote-font").value = state.quote; $("spec-font").value = state.spec;
    $("title-italic").checked = state.ti; $("quote-italic").checked = state.qi; $("cite-italic").checked = state.ci;
    $("card-width").value = state.width; $("side").checked = state.side;
    $("as").value = state.as; $("ay").value = state.ay;
    $("as-out").textContent = (+state.as).toFixed(2); $("ay-out").textContent = (+state.ay).toFixed(3);
    applyCard(); showView(); if (save) persist();
    measureAlephSpan().catch(() => {});
  }
  $("reset").onclick = () => {
    try { localStorage.removeItem(STORE_KEY); } catch (e) { /* ignore */ }
    try { history.replaceState(null, "", location.pathname); } catch (e) { /* ignore */ }
    Object.assign(state, defaults());
    setAll(false);   // controls back to the defaults, nothing written until the next change
  };
  $("aleph").addEventListener("change", e => {
    if (e.target.id === "aw") { state.aw = e.target.value; setAll(); }
    else if (e.target.dataset.af) {
      const n = e.target.dataset.af, on = e.target.checked;
      state.af = faceRank(state.aw).filter(x => x === n ? on : state.af.includes(x));
      setAll();
    }
  });
  $("aleph").addEventListener("click", e => {
    const b = e.target.closest("button[data-a]"); if (!b) return;
    const order = faceRank(state.aw);
    state.af = b.dataset.a === "top6" ? order.slice(0, 6) : b.dataset.a === "all" ? [...order] : [];
    setAll();
  });
  $("as").oninput = e => { state.as = String(Math.round(+e.target.value * 100) / 100); setAll(); };
  $("ay").oninput = e => { state.ay = String(Math.round(+e.target.value * 1000) / 1000); setAll(); };
  $("title-font").onchange = e => { state.title = e.target.value; setAll(); };
  $("quote-font").onchange = e => { state.quote = e.target.value; setAll(); };
  $("spec-font").onchange = e => { state.spec = e.target.value; setAll(); };
  $("title-weight").onchange = e => { state.tw = e.target.value; setAll(); };
  $("quote-weight").onchange = e => { state.qw = e.target.value; setAll(); };
  $("title-italic").onchange = e => { state.ti = e.target.checked; setAll(); };
  $("cite-italic").onchange = e => { state.ci = e.target.checked; setAll(); };
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
