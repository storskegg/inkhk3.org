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

## TODO

- Implement automatic Cloudfront invalidations for paths of changed files, on successful deploy.
- Implement something esoteric.

## Credits

Please find, below, a list of open source projects that I've used in this project. All copyrights belong to their
respective owners. Anything listed below that is incorporated into this repo may have been modified from its original
form to suit the needs of this project.

- Mark-Jan Nederhof's excellent [ResJS](https://github.com/nederhof/resjs) library to render hieroglyphs beautifully.
- Mark-Jan Nederhof's excellent fonts for hieroglyphs, transliteration, etc. All fonts found in Nederhof's ResJS repo
  have been incorporated in their original form into this repo.
