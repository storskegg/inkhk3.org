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

- Mark-Jan Nederhof's excellent [ResJS](https://github.com/nederhof/resjs) library to render hieroglyphs beautifully.
- `src/hierojax.js` (the hierojax library) is modified locally: rendered SVGs get a `viewBox` and em-based width/height
  so they scale with the font-size.
- Mark-Jan Nederhof's excellent fonts for hieroglyphs, transliteration, etc. All fonts found in Nederhof's ResJS repo
  have been incorporated in their original form into this repo.
