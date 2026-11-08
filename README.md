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

- Mark-Jan Nederhof's [hierojax](https://github.com/nederhof/hierojax) renders the hieroglyphs; see below.
- Mark-Jan Nederhof's [ResJS](https://github.com/nederhof/resjs) repository: `CaslonRoman.ttf`, `DejaVuSans-Bold.ttf`
  and `HieroglyphicAux.ttf` in `public/` are byte-identical (same git blob hashes) to the files in that repo, in their
  original form. ResJS itself no longer renders anything on this site.
- `UMSCH_S.TTF`, `UMSCH_SB.TTF`, `UMSCH_I.TTF` and `UMSCH_IB.TTF` (the Umschrift transliteration fonts) are not in
  ResJS or hierojax; their original source has not been confirmed.

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
