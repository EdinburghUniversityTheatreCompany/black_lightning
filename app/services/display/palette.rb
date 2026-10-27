require "vips" # Gemfile brings ruby-vips in, but nothing in the app
               # auto-requires it; without this the first extraction
               # raises NameError and the rescue would tombstone every
               # blob instead of extracting a palette.

module Display
  # The key colours of an event's artwork, for the credits panel's ambient
  # background. Runs over a small variant of the poster with ruby-vips (already
  # in the stack for ActiveStorage variants), quantises the pixels into coarse
  # RGB buckets and returns the most common distinct ones.
  #
  # Posters vary wildly in saturation (a faded photo vs a neon club night), so
  # the raw dominant colours would make the ambient wash swing between invisible
  # and blaring. The palette is therefore saturation-normalised: the image's own
  # mean saturation is measured and a gain maps it to a target, applied to every
  # palette colour (hue and brightness kept, gain clamped so neither muted
  # posters get falsely vivid nor neon ones stay blaring).
  #
  # The result is cached on the blob's metadata: Anthias polls these pages
  # continuously, and extracting a palette per render would hammer storage.
  # Handles every content type the event model accepts except GIF (excluded
  # from production use): PNG (RGB, RGBA, greyscale, 16-bit), JPEG (incl.
  # CMYK) and WebP. libvips autodetects the container from magic bytes.
  class Palette
    VARIANT_SIZE = 64 # px; enough for colour counts, cheap to decode
    BUCKET = 32       # each channel quantised to 8 steps, so near-identical
                      # pixels collapse into one colour

    class << self
      def for(event)
        blob = preview_blob(event)
        return nil unless blob

        cached = blob.metadata["palette_v2"]
        # Any cached palette is trusted: extract can legitimately return 1 or 2
        # colours (uniform posters), and false is the tombstone left by a failed
        # extraction. Only nil means "never tried"; the helper's blank? copes with
        # both false and empty arrays, rendering the plain black panel.
        return cached unless cached.nil?

        palette = extract(blob)
        blob.update!(metadata: blob.metadata.merge("palette_v2" => palette))
        palette
      rescue StandardError => e
        Rails.logger.warn("Display::Palette failed: #{e.class}: #{e.message}")
        # Tombstone the failure so a permanently broken blob isn't re-downloaded
        # and re-decoded on every render.
        blob.update!(metadata: blob.metadata.merge("palette_v2" => false)) rescue nil
        nil
      end

      private

      # The image the Next Event panel shows, so the credits' colours describe
      # what the kiosk's audience is actually looking at.
      def preview_blob(event)
        image = event.fetch_image
        return nil unless image

        image.blob # resized here anyway; an unprocessed variant has no blob
      end

      # Five vertical bands (top/mid/low thirds weighted to where titles and
      # faces sit), bucketed per pixel, most common distinct bucket per band.
      TARGET_SATURATION = 0.45 # post-gain mean saturation, on the 0-1 HSV scale
      GAIN_MIN = 0.6           # clamp: neon posters are tamed, not greyed out
      GAIN_MAX = 2.2           # ...and faded ones lifted, not falsified
      SAT_FLOOR = 0.12         # near-greys stay near-greys (keeps black & white
      SAT_CEIL = 0.85          # posters from getting an invented colour cast)

      def extract(blob)
        # All decoding happens inside the block: the temp file is deleted when
        # it exits, and vips executes lazily, so anything left un-forced would
        # read a file that no longer exists. copy_memory forces the decode and
        # detaches the result from the file entirely.
        image = blob.open do |file|
          img = Vips::Image.new_from_file(file.path)
          # Drop any alpha band, however it arrives (RGBA, grey+alpha, CMYK+alpha):
          # it shifts the bands and its transparent pixels skew the bucket counts.
          # No access: :sequential here - extract reads the image several times
          # (band crops plus a full pass for mean_saturation), and sequential
          # access only permits one top-to-bottom pass, so re-reads raise.
          img = img.flatten if img.has_alpha?
          img = img.colourspace(:srgb).resize(
            VARIANT_SIZE.to_f / [img.width, 1].max
          )
          # 16-bit sources (a 16-bit PNG upload) arrive as ushort, 0-65535.
          # cast(:uchar) clips rather than scales, destroying mid-tones, so
          # scale to 0-255 first; every later step assumes 8-bit pixels.
          img = img.linear(1 / 257.0, 0).cast(:uchar) if img.format == :ushort
          # A truly monochrome source (greyscale PNG/JPEG) stays 1-band even in
          # sRGB; band_pixels would then bucket 1-element keys and rgb_to_hsv
          # would raise, tombstoning every greyscale poster. Replicate to RGB.
          if img.bands == 1
            grey = img[0]
            img = grey.bandjoin([grey, grey])
          end
          img.copy_memory
        end

        height = image.height
        band = (height / 3.0).ceil
        colours = [0, band, 2 * band].filter_map do |top|
          band_pixels(image, top, band)
        end.first(3)

        normalise_saturation(colours, mean_saturation(image))
      end

      # Mean HSV saturation across the whole image (S band of the full small
      # variant, alpha already flattened above).
      def mean_saturation(image)
        hsv = image.colourspace(:hsv)
        s = hsv.extract_band(1)
        s.avg / 255.0
      rescue Vips::Error
        0.5 # unknown; unity-ish gain
      end

      # Scale each colour's saturation by the gain that would move the image's
      # mean to TARGET, keeping hue/value and the colours' relative ordering.
      def normalise_saturation(colours, mean_s)
        gain = (TARGET_SATURATION / [mean_s, 0.01].max).clamp(GAIN_MIN, GAIN_MAX)
        colours.map do |rgb|
          h, sat, v = rgb_to_hsv(*rgb)
          # A true grey (s ~ 0) has no hue to protect; leave it grey rather
          # than let the floor invent a colour cast on mono posters.
          next rgb if sat <= 0.02

          hsv_to_rgb(h, (sat * gain).clamp(SAT_FLOOR, SAT_CEIL), v)
        end
      end

      # Small integer helpers on 0-255 RGB / 0-1 HSV. Palette colours number
      # three per poster, so clarity beats speed here.
      def rgb_to_hsv(r, g, b)
        r, g, b = [r, g, b].map { |c| c / 255.0 }
        max = [r, g, b].max
        min = [r, g, b].min
        delta = max - min
        h = if delta.zero?
              0.0
            else
              case max
              when r then ((g - b) / delta) % 6
              when g then (b - r) / delta + 2
              else (r - g) / delta + 4
              end * 60
            end
        [h, max.zero? ? 0 : delta / max, max]
      end

      def hsv_to_rgb(h, s, v)
        c = v * s
        x = c * (1 - ((h / 60.0) % 2 - 1).abs)
        m = v - c
        rgb = case h
              when 0...60 then [c, x, 0]
              when 60...120 then [x, c, 0]
              when 120...180 then [0, c, x]
              when 180...240 then [0, x, c]
              when 240...300 then [x, 0, c]
              else [c, 0, x]
              end
        rgb.map { |f| ((f + m) * 255).round }
      end

      def band_pixels(image, top, band)
        top = [[top, 0].max, image.height - 1].min
        rows = [band, image.height - top].min
        region = image.crop(0, top, image.width, rows)
        counts = Hash.new(0)
        # to_a returns rows of pixels, so iterate both levels; keep RGB only
        # (a fourth band, when present, would skew the buckets).
        region.to_a.each do |row|
          row.each do |px|
            # to_i first: interpolation can yield Floats, and float division
            # would make (v / BUCKET) * BUCKET a no-op, defeating quantisation.
            key = px.first(3).map { |v| (v.to_i / BUCKET) * BUCKET }
            counts[key] += 1
          end
        end
        counts.max_by { |_, n| n }&.first&.map(&:to_i)
      end
    end
  end
end
