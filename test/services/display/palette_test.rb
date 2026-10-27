require "test_helper"

module Display
  class PaletteTest < ActiveSupport::TestCase
    test "extract pulls the dominant colour of each third of the artwork" do
      blob = palette_blob do |img|
        # Three distinct bands: red top, green middle, blue bottom. Broad enough
        # that each band's majority bucket is unambiguous after quantisation.
        # 60x60 in thirds of 20 rows: thumbnail(64) leaves it at 60 (it does not
        # upscale), so band = 60/3 = 20 lands each region inside one colour.
        bands = [ [255, 0, 0], [0, 200, 0], [0, 0, 255] ].map do |r, g, b|
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
      assert_operator green[1], :>, [green.first, green.last].max, "middle band must be green-dominant"
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
      pale = normalise([[ 250, 230, 220 ]], 0.2)

      # HSV value is the brightest channel; the cap is MAX_VALUE on the 0-1
      # scale, so the returned 0-255 pixel may not exceed it.
      assert_operator pale.first.max, :<=, (Palette::MAX_VALUE * 255).round,
                      "a pale poster must tint the panel, not whitewash it"
    end

    test "normalise_saturation leaves a grey artwork with no wash" do
      assert_equal [], normalise([[ 128, 128, 128 ], [ 130, 128, 126 ], [ 128, 129, 130 ]], 0.05)
    end

    test "normalise_saturation keeps a true grey grey instead of inventing a cast" do
      colours = normalise([[ 128, 128, 128 ], [ 90, 90, 92 ], [ 10, 0, 255 ]], 0.02)
      assert_equal [128, 128, 128], colours.first, "a true grey keeps its hue (none) under any gain"
    end

    test "for reads the cached palette and nothing else" do
      event = FactoryBot.create(:event, attach_image: false)
      assert_nil Display::Palette.for(event)

      event.image.attach(io: StringIO.new("stub"), filename: "poster.png", content_type: "image/png")
      event.image.blob.update!(metadata: { "palette_v2" => [ [255, 0, 0], [0, 255, 0], [0, 0, 255] ] })

      assert_equal [ [255, 0, 0], [0, 255, 0], [0, 0, 255] ], Display::Palette.for(event)
    end

    test "extract! tombstones an undecodable blob so it is never retried" do
      event = FactoryBot.create(:event, attach_image: true)
      blob = event.image.blob
      blob.update!(metadata: blob.metadata.merge("content_type" => "image/png"))
      stub_file(blob, "this is not an image")

      assert_changes -> { blob.reload.metadata["palette_v2"] } do
        Display::Palette.extract!(blob)
      end
      assert_equal false, blob.metadata["palette_v2"]
    end

    private

    # normalise_saturation is deliberately private (the render path must only
    # ever read the cache), so reach it from the test the honest way.
    def normalise(colours, mean_s)
      Palette.send(:normalise_saturation, colours, mean_s)
    end

    # Builds a blob whose file is the image vips builds in the block, through
    # the same Active Storage path a real upload takes.
    def palette_blob
      # linear() promotes to float; real uploads are 8-bit, and colourspace(:hsv)
      # only accepts uchar, so pin the format the pipeline expects.
      png = yield.cast(:uchar).to_blob(".png")
      event = FactoryBot.create(:event, attach_image: false)
      event.image.attach(io: StringIO.new(png), filename: "poster.png", content_type: "image/png")
      event.image.blob
    end

    # Points a blob's service at a given string (extract! opens the blob; the
    # attached file's bytes are whatever the factory put there). A Tempfile:
    # Vips::Image.thumbnail reads by path, so the fake must behave like a file.
    def stub_file(blob, content)
      blob.define_singleton_method(:open) do |&block|
        file = Tempfile.new(["blob", ".bin"])
        file.write(content)
        file.close
        begin
          block.call(file)
        ensure
          file.unlink
        end
      end
    end
  end
end
