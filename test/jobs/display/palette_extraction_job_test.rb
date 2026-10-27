require "test_helper"

module Display
  class PaletteExtractionJobTest < ActiveSupport::TestCase
    # Mocha-style stubbing is not in the stack: swap extract! for one that
    # fails the test if the job ever calls it, then put the real one back.
    def forbid_extraction!
      @original_extract = Palette.method(:extract!)
      Palette.define_singleton_method(:extract!) { |*| raise "Palette.extract! must not run for this job" }
    end

    teardown do
      if @original_extract
        original = @original_extract
        Palette.define_singleton_method(:extract!) { |*args| original.call(*args) }
        @original_extract = nil
      end
    end

    test "extracts for an event with a fresh uploaded artwork" do
      event = FactoryBot.create(:event, attach_image: true)
      assert event.image.blob.metadata["palette_v2"].nil?

      Display::PaletteExtractionJob.perform_now(event)

      assert_not_nil event.image.blob.reload.metadata["palette_v2"],
                     "a successful extraction must cache the palette on the blob"
    end

    test "skips a blob it has already handled" do
      event = FactoryBot.create(:event, attach_image: true)
      event.image.blob.update!(metadata: { "palette_v2" => [] })
      forbid_extraction!

      Display::PaletteExtractionJob.perform_now(event)

      assert_equal [], event.image.blob.reload.metadata["palette_v2"]
    end

    test "does nothing for an event with no artwork" do
      event = FactoryBot.create(:event, attach_image: false)
      forbid_extraction!

      Display::PaletteExtractionJob.perform_now(event)
    end

    test "skips the fetch_image placeholder" do
      event = FactoryBot.create(:event, attach_image: true)
      # Force the blob's filename onto the placeholder prefix: the factory
      # uploads a real file, but the same rule must hold for fetched art.
      event.image.blob.update!(filename: ActiveStorageHelper::PREFIX + "/cover.png")
      forbid_extraction!

      Display::PaletteExtractionJob.perform_now(event)
    end
  end
end
