# Font lab (local only)

Try serif web fonts with real Unicode Egyptological transliteration against the site's card, next to
today's card (Umschrift title + system serif quote). Nothing here is built or deployed: it lives in
`lab/`, outside Vite's `src/` and `public/`, and `deploy.sh` aborts if anything lab-like shows up in
`dist/` (checked by `test/deploy-order.sh`).

## Run

```sh
FONTTOOLS_PY=/path/to/venv/bin/python lab/fetch-fonts.sh   # once; idempotent, ~150 MB incl. download cache
"$FONTTOOLS_PY" -I lab/check-coverage.py                   # writes lab/fonts.json from the cmap tables
npm run lab                                                # http://localhost:8081/
```

`FONTTOOLS_PY` is any Python with `fontTools` and `brotli`. `npm run lab` runs
`serve -host 127.0.0.1 -port 8081 -dir lab` (this machine's `serve` is the Go one at
`/opt/homebrew/bin/serve`: it takes `-port`, not `-l`, and flags must come before the directory).
`localhost:8080` (`serve dist`) is untouched.

## What is where

- `manifest.tsv`: every font file, its pinned release URL and sha256. `fetch-fonts.sh` verifies the hash,
  converts each style to woff2 (lossless, no subsetting) into `fonts/<name>/<style>.woff2` and keeps the
  licence file as `licence.lic`. It also copies today's `UMSCH_*.woff2` into `fonts/umschrift/` and copies
  `hierojax.js`, `NewGardiner.woff2`, `paper_fff.jpg`, `binding_dark2.png` and the hierojax CSS to `lab/`.
  The hieroglyph lines are rendered by the real hierojax, exactly like the site.
- `fonts-meta.json`: hand-written source, licence and notes per font. `check-coverage.py` merges it with
  what it reads from the font files into `fonts.json` (coverage per style, woff2 sizes, name-table licence,
  weight axis). Coverage is from the cmap, never from rendering.
- `index.html`, `lab.css`, `lab.js`: static, no build, no CDN, no third-party requests.
  Pickers for title and quote, weight and italic (`font-synthesis: none`, so a missing bold or italic is
  shown as the nearest real face), card width, side-by-side toggle, a specimen view (missing glyphs boxed
  in red from the cmap data, with a monospace fallback behind each font) and a table of all candidates.
  State lives in the URL (`?title=junicode&quote=charis&side=1&view=specimen`).
- The title uses real Unicode ("Ink Ḥkꜣ {.org}") for candidates and the keyboard-encoded string
  ("Ink Ok# {.Órg}") for Umschrift.

## Adding a font

Add its rows to `manifest.tsv` (pin a release, run `shasum -a 256` once) and an entry to
`fonts-meta.json`, then rerun the two scripts. Brill is listed in the meta file only: its download page
refuses scripted fetches and its licence is restricted for web use.
