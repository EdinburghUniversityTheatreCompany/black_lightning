require "test_helper"

module Display
  class PaletteTest < ActiveSupport::TestCase
    test "extract pulls the dominant colour of each third of the artwork" do
      blob = palette_blob do |img|
        # Three distinct bands: red top, green middle, blue bottom. Broad enough
        # that each band's majority bucket is unambiguous after quantisation.
        # 60x60 in thirds of 20 rows: thumbnail(64) leaves it at 60 (it does not
        # upscale), so band = 60/3 = 20 lands each region inside one colour.
        bands = [ [ 255, 0, 0 ], [ 0, 200, 0 ], [ 0, 0, 255 ] ].map do |r, g, b|
          Vips::Image.black(60, 20, bands: 3).linear(0, [ r, g, b ])
        end
        bands[0].join(bands[1], :vertical).join(bands[2], :vertical)
      end

      palette = Palette.extract(blob)

      assert_equal 3, palette.size
      # Exact values depend on the saturation gain, so assert the hue per band:
      # the top band's colour is red-dominant, and so on down.
      red, green, blue = palette
      assert_operator red.first, :>, red.drop(1).max, "top band must be red-dominant"
      assert_operator green[1], :>, [ green.first, green.last ].max, "middle band must be green-dominant"
      assert_operator blue.last, :>, blue.take(2).max, "bottom band must be blue-dominant"
    end

    test "extract reads a greyscale artwork without raising" do
      blob = palette_blob do
        Vips::Image.black(64, 64).linear(1.0, 128) # uniform mid-grey
      end

      # Nothing colourful to paint with: the wash is skipped, cache empty.
      assert_equal [], Palette.extract(blob)
    end

    test "normalise_saturation caps a pale colour's brightness" do
      pale = normalise([ [ 250, 230, 220 ] ], 0.2)

      # HSV value is the brightest channel; the cap is MAX_VALUE on the 0-1
      # scale, so the returned 0-255 pixel may not exceed it.
      assert_operator pale.first.max, :<=, (Palette::MAX_VALUE * 255).round,
                      "a pale poster must tint the panel, not whitewash it"
    end

    test "normalise_saturation leaves a grey artwork with no wash" do
      assert_equal [], normalise([ [ 128, 128, 128 ], [ 130, 128, 126 ], [ 128, 129, 130 ] ], 0.05)
    end

    test "normalise_saturation keeps a true grey grey instead of inventing a cast" do
      colours = normalise([ [ 128, 128, 128 ], [ 90, 90, 92 ], [ 10, 0, 255 ] ], 0.02)
      assert_equal [ 128, 128, 128 ], colours.first, "a true grey keeps its hue (none) under any gain"
    end

    test "for reads the cached palette and nothing else" do
      event = FactoryBot.create(:event, attach_image: false)
      assert_nil Display::Palette.for(event)

      event.image.attach(io: StringIO.new("stub"), filename: "poster.png", content_type: "image/png")
      event.image.blob.update!(metadata: { "palette_v2" => [ [ 255, 0, 0 ], [ 0, 255, 0 ], [ 0, 0, 255 ] ] })

      assert_equal [ [ 255, 0, 0 ], [ 0, 255, 0 ], [ 0, 0, 255 ] ], Display::Palette.for(event)
    end

    test "extract reads a poster with transparency" do
      blob = palette_blob do
        opaque = Vips::Image.black(60, 20, bands: 3)
        # Red over a see-through middle over blue; flattening must not shift the bands.
        bands = [ opaque.linear(0, [ 255, 0, 0 ]), opaque, opaque.linear(0, [ 0, 0, 255 ]) ]
        alpha = [ 255, 0, 255 ].map { |a| Vips::Image.black(60, 20).linear(0, a) }
        bands.zip(alpha).map { |rgb, a| rgb.bandjoin(a) }.reduce { |top, below| top.join(below, :vertical) }
      end

      top, _middle, bottom = Palette.extract(blob)

      assert_operator top.first, :>, top.drop(1).max, "top band must stay red-dominant"
      assert_operator bottom.last, :>, bottom.take(2).max, "bottom band must stay blue-dominant"
    end

    # cast(:uchar) clips 16-bit values instead of scaling them, which turns orange into yellow.
    test "extract scales a 16-bit poster rather than clipping it" do
      blob = palette_blob(format: :ushort) do
        Vips::Image.black(60, 60, bands: 3).linear(0, [ 200 * 257, 100 * 257, 0 ])
      end

      red, green, blue = Palette.extract(blob).first

      assert_operator green, :<, red * 0.75, "orange must not come back yellow"
      assert_operator blue, :<, green
    end

    # The job runs beside ActiveStorage's AnalyzeJob, and both save the whole metadata hash.
    test "extract! merges into the row as saved now, not the copy it was handed" do
      blob = palette_blob { Vips::Image.black(60, 60, bands: 3).linear(0, [ 200, 40, 40 ]) }
      stale = ActiveStorage::Blob.find(blob.id)
      blob.update!(metadata: blob.metadata.merge("analyzed" => true, "width" => 60, "height" => 60))

      Palette.extract!(stale)

      metadata = blob.reload.metadata
      assert_equal 60, metadata["width"], "the analysis's keys must survive the palette write"
      assert metadata["palette_v2"].present?
    end

    private

    # normalise_saturation is deliberately private (the render path must only
    # ever read the cache), so reach it from the test the honest way.
    def normalise(colours, mean_s)
      Palette.send(:normalise_saturation, colours, mean_s)
    end

    # Builds a blob whose file is the image vips builds in the block, through
    # the same Active Storage path a real upload takes.
    def palette_blob(format: :uchar)
      # linear() promotes to float, so pin the format the upload would have: 8-bit by
      # default, or 16-bit (:ushort) to test the scaling.
      png = yield.cast(format).write_to_buffer(".png")
      event = FactoryBot.create(:event, attach_image: false)
      event.image.attach(io: StringIO.new(png), filename: "poster.png", content_type: "image/png")
      event.image.blob
    end
  end
end
