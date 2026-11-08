# inkhk3.org
Source for inkhk3.org website.

There's really not much to see here. There's no front end application. The closest there is to a build process is
the compilation of the SCSS to CSS using npm scripts. I was, however, using this repo as an opportunity to play
with Terraform, which I've never really done before. It's basic...push files to S3, update CloudFront, Route53, etc.

I'm entertained that, given the utter simplicity of the website itself, the terraform scripts represent, as of
2025-12-21, 54% of the repo hahahahaha!!!

## Some Notes

- There are strange Unicode characters used on this site. These characters are used in Egyptian transliteration.
- The title of the site, "Ink Ḥkꜣ," is pronounced "EE-nuk Hekah," and translates to "I am Heka." 
- The quote on the page is from the ancient Egyptian "Book of Amduat," as translated by Robert K. Ritner in his 
  "The Mechanics of Ancient Egyptian Magical Practice," which itself cites Hornung, 1963. I find this statement quite 
  lovely. "May your words occur; may your magic shine."

## Developing

Needs node 24.x. Run these from the project root:

    npx serve        # the font lab (lab/) with live reload: http://127.0.0.1:8081/
    npx serve-dist   # builds, then serves the built site (vite preview): http://127.0.0.1:8080/
    npm run dev      # the site's own dev server (src/, public/): http://127.0.0.1:8083/

`npx serve` runs `vite --config vite.lab.config.ts`: CSS changes in `lab/` are hot-swapped, HTML and JS changes reload
the page. The lab is never built or deployed (see `lab/README.md`). `npm run dev` (alias `npm start`) is the site's dev
server: SCSS is hot-swapped, HTML and JS reload. Neither touches `dist/`. `npx serve` and `npx serve-dist` work because
`package.json` has a `bin` field (`bin/serve.mjs`, `bin/serve-dist.mjs`) that runs the npm scripts of the same name, so
they only work in this project's root (Node 24); elsewhere `npx serve` would fetch the public `serve` package. The npm
scripts do the same: `npm run serve` (alias `npm run lab`) and `npm run serve-dist`. Extra flags pass through, e.g.
`npx serve --port 8090`.

## Deploying

Content is published by `deploy.sh`, not Terraform. Terraform manages only the infrastructure (bucket, CloudFront,
Route53, certificates).

    aws login        # if your session has expired
    ./deploy.sh          # builds, then shows a dry run of the S3 sync; changes nothing
    ./deploy.sh --live   # builds, syncs to S3, then invalidates the changed paths in CloudFront

The script needs node 24.x (it tries `nvm use` itself) and the `aws` CLI. It sets content types for fonts and the web
manifest, long immutable caching for the hashed `index-*.js/css`, and a short cache for everything else.

Order: it uploads without deleting (assets, fonts, then `index.html` last), invalidates CloudFront and waits for that,
and only then deletes stale keys, keeping hashed `index-*.js/css` uploaded in the last 24 hours (the previous deploy's pair).
`test/deploy-order.sh` runs `deploy.sh` and `--live` against a fake `aws` (`test/fake-aws.sh`) and checks that order;
it needs node 24 and calls no AWS.

### One-time migration

The S3 objects used to be Terraform resources. A `removed` block in `modules/S3/main.tf` (with `destroy = false`)
hands them over without deleting anything from the bucket. Once, before the first apply:

1. `terraform plan`, and confirm it says **0 to destroy** (the objects should only be "forgotten").
2. `terraform apply`.

After that, use `./deploy.sh` for all content changes.

## TODO

- Implement something esoteric.

## Credits

Please find, below, a list of open source projects that I've used in this project. All copyrights belong to their
respective owners. Anything listed below that is incorporated into this repo may have been modified from its original
form to suit the needs of this project.

- InkHk3 Serif (`InkHk3Serif-Bold.woff2` and `InkHk3Serif-Italic.woff2` in `public/`) is derived from
  [New Athena Unicode](https://apagreekkeys.org/NAUdownload.html) 5.008 by the Society for Classical Studies (formerly the
  American Philological Association), licensed under the SIL Open Font License 1.1, with Reserved Font Name "New Athena
  Unicode". Copyright (c) 2004-2015 Society for Classical Studies (the licence file's line; the font's name table says
  2016-2021). Source: <https://apagreekkeys.org/fonts/NAU5_008.zip> (sha256 `cdfe5c38...6e7bbf1`). The files are
  Modified Versions of `newathuBold5_8.ttf` and `newathuItalic5_8.ttf`, so they carry another name, the reserved
  one not being usable. What changed: the family renamed (the `name` table, plus a modification note in name ID 10),
  and the conversion to woff2 (DSIG dropped, glyf and loca rebuilt, head flag and modified date changed). No
  subsetting, no other change: outlines, hinting, metrics and all other tables are the original's (byte-identical,
  except glyf and loca, which are the same outlines stored again by the converter). `fonts/make-inkhk3-serif.py` makes
  them from the zip (checks its sha256 and that no table of the output contains the old name):
  `python3 -I fonts/make-inkhk3-serif.py NAU5_008.zip public/` (needs fontTools and brotli). The licence text, as the
  original states it, plus the list of changes, is `public/InkHk3Serif-OFL.txt`, served at
  <https://inkhk3.org/InkHk3Serif-OFL.txt>. It sets the title, the quote and the citation (real Unicode
  transliteration: "Ink Ḥkꜣ", U+1E24 and U+A723).
- Mark-Jan Nederhof's [hierojax](https://github.com/nederhof/hierojax) renders the hieroglyphs; see below.

The title's ꜣ is enlarged (see "The enlarged ꜣ" below). The earlier fonts (Umschrift, and the ResJS fonts
`CaslonRoman.ttf`, `DejaVuSans-Bold.ttf`, `HieroglyphicAux.ttf`, which nothing used any more) are no longer in `public/`
and no longer credited; Umschrift stays in git history and in the lab (`lab/README.md`).

### Fonts

- **The enlarged ꜣ.** InkHk3 Serif's ꜣ is small next to the title's capitals (1.30 x-heights tall, top at 0.80 of the cap
  height); Umschrift's was 1.48 and 0.98. The title's ꜣ is `<span class="aleph">ꜣ</span>`, scaled 1.18 and lifted
  0.037em with a CSS transform (origin: the glyph's left side bearing and the baseline), which does not touch the
  line box or the advance width, so the baseline does not move and ".org" only moves by the span's 0.03em left margin (added because the larger hook otherwise touched the k). Result (ink, measured): 0.63 em, 1.54
  x-heights tall, top at 1.01 of the cap height, bottom 0.03 em above the baseline. Tuned in the lab (`lab/README.md`).
- **font-display.** The title uses the family `InkHk3Serif` with `font-display: block`: its width is reserved in
  em (`.title-text`, 5.79em, measured from the rendered title) and its fallback face has InkHk3 Serif's ascent and
  descent, so the invisible-then-swapped title moves nothing. The quote and the citation use `InkHk3SerifText`
  (same files, so one download each) with `font-display: optional`: their line breaks depend on the font, and a
  late swap would re-wrap them and shift the card. Both faces are preloaded; if they are not ready in about 100 ms
  the quote and citation stay in the system serif for that page view (as before this change) and get InkHk3 Serif from
  the next view on. Switch `optional` to `swap` in `src/_fonts.scss` to trade that for a small shift on slow loads.
- Only two faces are shipped (Bold: title and quote, the quote's 900 resolves to it; Italic: `<cite>`), 400 KB in all.

### hierojax

`src/hierojax.js` is [hierojax](https://github.com/nederhof/hierojax/tree/da318801e00b10b4b5c5ec8d9cc6f8fddcc9eb5a)
(`docs/hierojax.js` at commit da31880) by Mark-Jan Nederhof, licensed GPL-3.0. `src/_hierojax.scss` is its
`docs/hierojax.css` at the same commit, with the `@font-face` rule removed: the `Hieroglyphic` font is registered only by `src/hierojax.js` (see (c)), so it loads once.

Local modifications to `src/hierojax.js`; the complete diff is `vendor/hierojax.local.patch` (the file header says how to
apply and regenerate it):

- (a) `PrintedSVG` constructor, right after the `width`/`height` attributes are set: adds a `viewBox` of
  `0 0 width height` and, if `fontSize > 0`, sets the SVG's style width and height in `em` (`size / fontSize`).
  Why: the rendered SVG then scales with the container's font-size after rendering (resize, rotation).
- (b) End of the file: adds a `DOMContentLoaded` listener that calls `hierojax.processFragments()`. Why: upstream leaves
  that call to the page; here it starts automatically.
- (c) Font file name and format, so the font loads once: the `FontFace('Hieroglyphic', ...)` URL in
  `startLoadingFonts()` is `/NewGardiner.woff2` (was `NewGardiner.otf`), `PrintedSVG.EXTERNAL_FONT` is
  `'/NewGardiner.woff2'` (was `'NewGardiner.otf'`), and `PrintedSVG.internalCSS()` says `format('woff2')` (was
  `format('opentype')`). The absolute path is deliberate.
- (d) `public/NewGardiner.woff2` is upstream's `docs/NewGardiner.otf` converted to WOFF2 with fontTools
  (`fonttools ttLib.woff2 compress`). No other changes to the font (no subsetting).
