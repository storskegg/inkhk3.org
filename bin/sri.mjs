#!/usr/bin/env node
// Subresource Integrity for the built site. No dependencies.
//
//   node bin/sri.mjs            hash dist/ in place (runs from `postbuild`, after postcss)
//   node bin/sri.mjs --check    change nothing; fail if any hash, name or reference is off
//   node bin/sri.mjs [--check] DIR   another build directory (tests)
//
// For every local <script src>, <link rel=stylesheet|modulepreload> and <link rel=preload as=script|style>
// in every *.html under DIR it adds integrity="sha384-..." (and crossorigin if missing), leaving the rest of
// the HTML byte-identical. Stylesheets named index-*.css are renamed to index-<8 chars of the base64url
// sha384 of their final bytes>.css, because Vite names the CSS before postcss/cssnano rewrites it: a name
// that does not follow the bytes would let an immutable-cached old copy fail the new integrity check.
// Fails (exit 1, nothing written) if a referenced file is missing, a tag points off-origin, or a *.js/*.css
// in DIR is not referenced by an integrity-bearing tag (it would ship unhashed). Fonts are not hashed: see README.
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, readdirSync, renameSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const args = process.argv.slice(2);
const CHECK = args.includes('--check');
const rest = args.filter((a) => a !== '--check');
if (rest.length > 1 || rest.some((a) => a.startsWith('-'))) {
  console.error('usage: sri.mjs [--check] [DIR]');
  process.exit(2);
}
const DIST = path.resolve(rest[0] ?? path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'dist'));
const errors = [];
const fail = (m) => errors.push(m);

const sha384 = (buf) => createHash('sha384').update(buf).digest();
const sri = (buf) => 'sha384-' + sha384(buf).toString('base64');
const cssName = (buf) => 'index-' + sha384(buf).toString('base64url').slice(0, 8) + '.css';

const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]);

if (!existsSync(DIST) || !statSync(DIST).isDirectory()) {
  console.error(`sri: ${DIST} does not exist; build first`);
  process.exit(1);
}
const files = walk(DIST);
const rel = (f) => path.relative(DIST, f);
const htmls = files.filter((f) => /\.html?$/i.test(f));
if (!htmls.length) fail('no *.html found in ' + DIST);

// --- find the tags -------------------------------------------------------------------------------------
const ATTR = /([^\s"'<>\/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
function parseTag(text, start, end) {
  // text[start..end) is "<name attrs>"; returns attrs with absolute spans
  const m = /^<(script|link)\b/i.exec(text.slice(start, end));
  const attrs = [];
  const body = text.slice(start + m[0].length, end - 1);
  const base = start + m[0].length;
  ATTR.lastIndex = 0;
  let a;
  while ((a = ATTR.exec(body))) {
    const val = a[2] ?? a[3] ?? a[4];
    const q = a[2] !== undefined ? '"' : a[3] !== undefined ? "'" : '';
    attrs.push({ name: a[1].toLowerCase(), value: val, start: base + a.index, end: base + a.index + a[0].length,
      valStart: val === undefined ? -1 : base + a.index + a[0].length - val.length - q.length, valEnd: base + a.index + a[0].length - q.length });
  }
  return { name: m[1].toLowerCase(), attrs };
}

function findTags(text) {
  const comments = [];
  for (const c of text.matchAll(/<!--[\s\S]*?(?:-->|$)/g)) comments.push([c.index, c.index + c[0].length]);
  const inComment = (i) => comments.some(([s, e]) => i >= s && i < e);
  const out = [];
  const re = /<(script|link)\b(?:"[^"]*"|'[^']*'|[^'">])*>/gi;
  let skipTo = 0;
  for (const m of text.matchAll(re)) {
    if (m.index < skipTo || inComment(m.index)) continue;
    const t = parseTag(text, m.index, m.index + m[0].length);
    if (t.name === 'script') {
      const close = text.toLowerCase().indexOf('</script', m.index + m[0].length);
      skipTo = close < 0 ? text.length : close; // inline script bodies are not markup
    }
    out.push({ ...t, start: m.index, end: m.index + m[0].length });
  }
  return out;
}

const attr = (t, n) => t.attrs.find((a) => a.name === n);
const isRemote = (u) => /^[a-z][a-z0-9+.-]*:/i.test(u) || u.startsWith('//');

// --- plan ----------------------------------------------------------------------------------------------
const pages = []; // { file, text, refs: [{tag, file (absolute, as it is now), urlAttr}] }
for (const html of htmls) {
  const text = readFileSync(html, 'utf8');
  const refs = [];
  for (const tag of findTags(text)) {
    let urlAttr, why;
    if (tag.name === 'script') {
      urlAttr = attr(tag, 'src'); why = '<script src>';
    } else {
      const relv = (attr(tag, 'rel')?.value ?? '').toLowerCase().split(/\s+/);
      const as = (attr(tag, 'as')?.value ?? '').toLowerCase();
      if (relv.includes('stylesheet') || relv.includes('modulepreload') || (relv.includes('preload') && (as === 'script' || as === 'style'))) {
        urlAttr = attr(tag, 'href'); why = `<link rel=${relv.join(' ')}>`;
      }
    }
    if (!urlAttr || urlAttr.value === undefined) continue;
    const where = `${rel(html)}: ${why} ${urlAttr.value}`;
    if (isRemote(urlAttr.value)) { fail(`${where}: points at another origin; this site is same-origin only`); continue; }
    const urlPath = urlAttr.value.split(/[?#]/)[0];
    let file;
    try { file = path.resolve(urlPath.startsWith('/') ? DIST : path.dirname(html), (urlPath.startsWith('/') ? '.' : '') + decodeURIComponent(urlPath)); }
    catch { fail(`${where}: bad URL`); continue; }
    if (file !== DIST && !file.startsWith(DIST + path.sep)) { fail(`${where}: leaves ${DIST}`); continue; }
    if (!existsSync(file) || !statSync(file).isFile()) { fail(`${where}: referenced file is missing`); continue; }
    refs.push({ tag, file, urlAttr, where });
  }
  pages.push({ file: html, text, refs });
}

// every js/css must be referenced
const referenced = new Set(pages.flatMap((p) => p.refs.map((r) => r.file)));
for (const f of files) {
  if (/\.(m?js|css)$/i.test(f) && !referenced.has(f)) {
    fail(`${rel(f)}: a script/stylesheet in the build that no integrity-bearing tag in any html references (a dynamic chunk? it would ship unhashed)`);
  }
}

// --- hashes, names, edits ------------------------------------------------------------------------------
const renames = new Map(); // old absolute -> new absolute
for (const f of referenced) {
  if (!/^index-.*\.css$/.test(path.basename(f))) continue;
  const want = path.join(path.dirname(f), cssName(readFileSync(f)));
  if (want !== f) renames.set(f, want);
}
if (CHECK) {
  for (const [from, to] of renames) fail(`${rel(from)}: name does not follow its bytes (expected ${path.basename(to)}); postcss ran after sri, or the file changed`);
} else {
  for (const [from, to] of renames) if (existsSync(to)) fail(`${rel(to)} already exists; cannot rename ${rel(from)}`);
  // nothing else in the build may mention an old name (a JS string, the manifest, ...)
  for (const f of files) {
    if (htmls.includes(f) || !/\.(m?js|css|json|webmanifest|txt|svg)$/i.test(f)) continue;
    const t = readFileSync(f, 'utf8');
    for (const from of renames.keys()) if (t.includes(path.basename(from))) fail(`${rel(f)} mentions ${path.basename(from)}, which would be renamed`);
  }
}

const newText = new Map();
let tagCount = 0;
for (const page of pages) {
  const edits = []; // [start, end, replacement]
  for (const r of page.refs) {
    tagCount++;
    const final = renames.get(r.file) ?? r.file;
    const bytes = readFileSync(r.file);
    const want = sri(bytes);
    const have = attr(r.tag, 'integrity');
    const cross = attr(r.tag, 'crossorigin');
    if (CHECK) {
      if (!have || have.value === undefined) fail(`${r.where}: no integrity attribute`);
      else if (have.value.trim() !== want) fail(`${r.where}: integrity does not match the file on disk (have ${have.value.trim()}, file is ${want})`);
      if (!cross) fail(`${r.where}: no crossorigin attribute`);
      continue;
    }
    // new URL
    if (final !== r.file) {
      const u = r.urlAttr.value, i = u.search(/[?#]/), p = i < 0 ? u : u.slice(0, i), s = i < 0 ? '' : u.slice(i);
      edits.push([r.urlAttr.valStart, r.urlAttr.valEnd, p.slice(0, p.lastIndexOf('/') + 1) + path.basename(final) + s]);
    }
    if (have) edits.push([have.start, have.end, `integrity="${want}"`]);
    else edits.push([r.urlAttr.end, r.urlAttr.end, ` integrity="${want}"` + (cross ? '' : ' crossorigin')]);
    if (have && !cross) edits.push([have.end, have.end, ' crossorigin']);
  }
  if (CHECK) continue;
  let t = page.text;
  for (const [s, e, rep] of edits.sort((a, b) => b[0] - a[0] || b[1] - a[1])) t = t.slice(0, s) + rep + t.slice(e);
  for (const from of renames.keys()) if (t.includes(path.basename(from))) fail(`${rel(page.file)} still mentions ${path.basename(from)} outside a tag`);
  newText.set(page.file, t);
}

if (errors.length) {
  console.error(`sri${CHECK ? ' --check' : ''}: FAILED (${errors.length})`);
  for (const e of errors) console.error('  - ' + e);
  process.exit(1);
}
if (CHECK) {
  console.log(`sri --check: ok (${tagCount} tag(s) in ${pages.length} html file(s))`);
  process.exit(0);
}
for (const [from, to] of renames) { renameSync(from, to); console.log(`sri: ${rel(from)} -> ${rel(to)}`); }
for (const [f, t] of newText) if (t !== pages.find((p) => p.file === f).text) writeFileSync(f, t);
console.log(`sri: hashed ${tagCount} tag(s) in ${pages.length} html file(s)`);
