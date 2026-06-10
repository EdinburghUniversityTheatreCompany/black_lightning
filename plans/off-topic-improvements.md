# Off-topic improvements

Items noticed while building the opportunities overhaul that are out of scope for it,
recorded for later. Each is optional.

## Opportunities feature follow-ups

- **Public submission can still create `Company` records freely.** A logged-out submitter (or any
  member) creates a `Company` via the `company_name` field on every submission. New companies are
  now flagged `reviewed: false` ("Needs review", prompted on approval), but they are still created
  up front, so the companies table can be polluted. Consider only creating the company on approval,
  deduping/merging in review, or rate-limiting.
  (`Opportunity#assign_company_from_name` / `Company.find_or_build_by_name`)

- **Honeypot uses `display:none`.** The public submission honeypot (`website_url`) is hidden with
  Tailwind `hidden` (display:none), which modern bots often skip. An off-screen technique
  (absolute + `left:-9999px`) catches more while staying invisible. reCAPTCHA is the primary
  defence, so this is a minor hardening. (`app/views/get_involved/new.html.erb`)

## Image processing follow-ups

- **`lib/RQRCode/renderers.rb` MiniMagick SVG path looks dead.** It calls
  `MiniMagick::Image.read(svg)`, which needs ImageMagick — installed neither locally nor in the
  Dockerfile (only `libvips`). The live mailer (`app/mailers/membership_mailer.rb`) uses the
  chunky_png `RQRCode::Renderers::PNG` renderer instead, so the MiniMagick path appears unused.
  If confirmed dead, remove the custom renderer (and possibly the `mini_magick` gem, once the
  representations controller no longer references `MiniMagick::Error`); otherwise add ImageMagick
  to the Docker image so it actually works.
