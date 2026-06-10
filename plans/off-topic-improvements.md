# Off-topic improvements

Items noticed while building the opportunities overhaul that are out of scope for it,
recorded for later. Each is optional.

## Image processing follow-ups

- **`lib/RQRCode/renderers.rb` MiniMagick SVG path looks dead.** It calls
  `MiniMagick::Image.read(svg)`, which needs ImageMagick — installed neither locally nor in the
  Dockerfile (only `libvips`). The live mailer (`app/mailers/membership_mailer.rb`) uses the
  chunky_png `RQRCode::Renderers::PNG` renderer instead, so the MiniMagick path appears unused.
  If confirmed dead, remove the custom renderer (and possibly the `mini_magick` gem, once the
  representations controller no longer references `MiniMagick::Error`); otherwise add ImageMagick
  to the Docker image so it actually works.
