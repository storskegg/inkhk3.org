# Font lab (local only)

Try serif web fonts with real Unicode Egyptological transliteration against the site's card, next to
today's card (Umschrift title + system serif quote). Nothing here is built or deployed: it lives in
`lab/`, outside Vite's `src/` and `public/`, and `deploy.sh` aborts if anything lab-like shows up in
`dist/` (checked by `test/deploy-order.sh`).

## Run

```sh
FONTTOOLS_PY=/path/to/venv/bin/python lab/fetch-fonts.sh   # once; idempotent, ~150 MB incl. download cache
"$FONTTOOLS_PY" -I lab/check-coverage.py                   # writes lab/fonts.json from the cmap tables
"$FONTTOOLS_PY" -I lab/measure-aleph.py                    # writes lab/aleph.json and lab/aleph-report.md
npx serve                                                  # http://127.0.0.1:8081/ , live reload
```

`FONTTOOLS_PY` is any Python with `fontTools` and `brotli` (`measure-aleph.py` also needs `Pillow`, `numpy` and `scipy`).
`npx serve` (Node 24, from the project root; `npm run serve` and `npm run lab` do the same) runs Vite's dev server
with `vite.lab.config.mts` (root `lab/`, no plugins, no public dir, no build): CSS edits are hot-swapped, JS and HTML
edits reload the page, and fonts, `hierojax.js` and the JSON files are served as they are. `serve-dist` uses 8080 and
the site's `npm run dev` 8083.

## What is where

- `manifest.tsv`: every font file, its pinned release URL and sha256. `fetch-fonts.sh` verifies the hash,
  converts each style to woff2 (lossless, no subsetting) into `fonts/<name>/<style>.woff2` and keeps the
  licence file as `licence.lic`. It also recovers Umschrift (the former site title font, kept as the "Today"
  reference) from git history into `fonts/umschrift/`: `git show 7f519e9:public/UMSCH_*.woff2`, the last commit
  that had them in `public/`, each checked against its sha256 (needs the full history, not a shallow clone), and
  copies `hierojax.js`, `NewGardiner.woff2`, `paper_fff.jpg`, `binding_dark2.png` and the hierojax CSS to `lab/`.
  The hieroglyph lines are rendered by the real hierojax, exactly like the site.
- `fonts-meta.json`: hand-written source, licence and notes per font. `check-coverage.py` merges it with
  what it reads from the font files into `fonts.json` (coverage per style, woff2 sizes, name-table licence,
  weight axis). Coverage is from the cmap, never from rendering.
- `index.html`, `lab.css`, `lab.js`: static, no build, no CDN, no third-party requests.
  Pickers for title and quote, weight and italic (`font-synthesis: none`, so a missing bold or italic is
  shown as the nearest real face), card width, side-by-side toggle, a specimen view (missing glyphs boxed
  in red from the cmap data, with a monospace fallback behind each font) and a table of all candidates.
  Every font list is sorted A-Z by family name (case-insensitive, locale compare); in the title, quote and specimen
  pickers today's references (Umschrift, the system serif) stay on top.
  State lives in the URL (`?title=junicode&quote=charis&side=1&view=specimen`).
- Serifs only: the sans-serif control (Andika) and its "sans control" code were removed. Doulos SIL is a serif and stays.
- **Aleph study** (`measure-aleph.py` -> `aleph.json`, `aleph-report.md`, both committed): for every serif with a real
  U+A723 it measures the ꜣ against Umschrift's (the glyph at `#`) from the outlines (size relative to x-height, cap
  height and the letter k, title width) and from a 400 px raster (number of ink pieces, gap between the hooks, stroke
  thickness against the font's own `I` stem, silhouette IoU), in the bold face (the title face; the regular one where
  there is no bold) and in regular, and ranks them by a documented score (formula in the report). Umschrift's `x` and
  `H` are not plain Latin (h-breve-below, H with a dot below), so its x-height comes from `z` and its cap height from `E`.
  The numbers are approximate; the score is a first filter, look at the Aleph view.
- **Aleph view** (`view=aleph`, button "Aleph"): per candidate a row with "Ink Ḥkꜣ" at 96 px and the ꜣ alone at 240 px,
  each next to Umschrift's "Ink Ok#" and "#" on the same baseline, with the baseline, x-height and cap height as faint
  guides (Umschrift's two heights repeated as red dashes). Pick the fonts with the checkboxes (default: top 6 by bold
  score; the checkboxes and rows are listed A-Z by family, with each font's rank and score kept in its label), "Top 6" (the top 6 by score) / "All" / "None", and a Bold / Regular toggle. URL: `af=<comma list>`, `aw=bold|regular`.
- **Enlarged title ꜣ** (panel, "Title ꜣ (enlarged)"): scale (1.00-1.40) and shift up in em (-0.10-0.20), URL `as`, `ay`.
  They are applied to a `<span class="aleph">` around the ꜣ in the candidate's title (and in the Aleph view's
  tuning block at the top: New Athena Bold plain, with the enlarged ꜣ, and Umschrift SB, same size and baseline,
  with the guides; below it the measured ink in em, x-heights and cap heights, from canvas `measureText`, against
  Umschrift's). The span is `inline-block; line-height: 0` with `transform: translateY() scale()`, so the line
  box and the advance do not change. The transform origin is New Athena Bold's (the ꜣ's left side bearing, 0.017em,
  and the baseline, 0.2835em below the zero-height box), so for other title fonts the scale is approximate.
  Defaults: scale 1.18, shift 0.037 em. The site uses scale 1.18 with no shift (`src/style.scss`; the lift was removed
  at the user's request on 2026-11-09).
  New Athena Unicode is the default title and quote font.
- **Settings persist.** Every control is saved to `localStorage` under one key, `inkhk3-lab` (JSON), and to the URL.
  On load, if the URL has any lab parameter the URL wins and storage is ignored (so shared links work); otherwise the
  stored values are used; otherwise the defaults. Every stored value is validated on its own: a missing or invalid
  value, or a font that is no longer in `fonts.json` (say a stale "andika"), falls back to that control's default and
  the other values are kept. Storage reads and writes are in try/catch (private mode, quota, bad JSON). The "Reset
  settings" button clears the key and the URL parameters and puts every control back to its default.
- The title uses real Unicode ("Ink Ḥkꜣ {.org}") for candidates and the keyboard-encoded string
  ("Ink Ok# {.Órg}") for Umschrift.

## Adding a font

Add its rows to `manifest.tsv` (pin a release, run `shasum -a 256` once) and an entry to
`fonts-meta.json`, then rerun the two scripts. Fonts that cannot be shipped are listed in the meta file only
(no manifest rows): Brill (download refused, restricted web licence), Quivira (redistribution only unaltered),
Palemonas (no download or terms found), TITUS Cyberbit Basic (non-commercial), Andron Scriptor Web (proprietary) and
Linguistics Pro (OFL, but no U+A722-A725). `extract.py` drops an empty `fpgm`/`prep`/`cvt ` table when converting
(BBAW Schoell ships an empty `fpgm`, which Chrome's sanitiser rejects).
