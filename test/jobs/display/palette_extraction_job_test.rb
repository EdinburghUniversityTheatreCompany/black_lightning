require "test_helper"

module Display
  class PaletteExtractionJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    # The factory's upload, analysed the way ActiveStorage's AnalyzeJob would.
    def analysed_event
      FactoryBot.create(:event, attach_image: true).tap { |event| event.image.blob.analyze }
    end

    test "extracts for an event with a fresh uploaded artwork" do
      event = analysed_event
      assert_nil event.image.blob.metadata["palette_v2"]

      Display::PaletteExtractionJob.perform_now(event)

      assert_not_nil event.image.blob.reload.metadata["palette_v2"],
                     "a successful extraction must cache the palette on the blob"
    end

    # AnalyzeJob saves the whole metadata hash from the copy it loaded, so a palette written
    # before it finishes is lost, and the panel stays black for good.
    test "waits for ActiveStorage's analysis before writing anything" do
      event = FactoryBot.create(:event, attach_image: true)
      assert_not event.image.blob.analyzed?

      assert_enqueued_with(job: Display::PaletteExtractionJob) do
        Display::PaletteExtractionJob.perform_now(event)
      end
      assert_not event.image.blob.reload.metadata.key?("palette_v2")
    end

    # A failed analysis never finishes, so the wait is capped.
    test "extracts anyway once the analysis has had its chances" do
      event = FactoryBot.create(:event, attach_image: true)
      job = Display::PaletteExtractionJob.new(event)
      job.executions = Display::PaletteExtractionJob::ANALYSIS_WAITS - 1

      assert_no_enqueued_jobs(only: Display::PaletteExtractionJob) { job.perform_now }
      assert event.image.blob.reload.metadata.key?("palette_v2")
    end

    test "keeps the analysis's width and height beside the palette" do
      event = analysed_event

      Display::PaletteExtractionJob.perform_now(event)

      metadata = event.image.blob.reload.metadata
      assert metadata["analyzed"]
      assert metadata["width"].present?, "ImageComponent reads the width for the <img> tag"
      assert metadata.key?("palette_v2")
    end

    test "marks a corrupt upload failed without raising, and the panel stays black" do
      event = FactoryBot.create(:event, attach_image: false)
      event.image.attach(io: StringIO.new("this is not an image"), filename: "poster.png", content_type: "image/png")
      event.image.blob.analyze

      Display::PaletteExtractionJob.perform_now(event)

      metadata = event.image.blob.reload.metadata
      assert metadata.key?("palette_v2"), "the tombstone stops a retry decoding it again"
      refute metadata["palette_v2"]
      assert_nil ApplicationController.helpers.display_ambient_gradient(event.reload)
    end

    test "skips a blob it has already handled" do
      event = analysed_event
      event.image.blob.update!(metadata: event.image.blob.metadata.merge("palette_v2" => []))

      Display::PaletteExtractionJob.perform_now(event.reload)

      assert_equal [], event.image.blob.reload.metadata["palette_v2"]
    end

    test "does nothing for an event with no artwork" do
      event = FactoryBot.create(:event, attach_image: false)

      Display::PaletteExtractionJob.perform_now(event)

      assert_not event.image.attached?, "the job must not attach anything when there is no artwork"
    end

    test "skips the fetch_image placeholder" do
      event = analysed_event
      # The factory uploads a real file; the placeholder is told apart by its filename alone.
      event.image.blob.update!(filename: "#{ActiveStorageHelper::PREFIX}/cover.png")

      Display::PaletteExtractionJob.perform_now(event.reload)

      assert_nil event.image.blob.reload.metadata["palette_v2"], "the placeholder prefix must stay unprocessed"
    end
  end
end
