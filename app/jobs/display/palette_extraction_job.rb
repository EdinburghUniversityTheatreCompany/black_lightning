module Display
  # Extracts the credits panel's ambient palette from an event's uploaded
  # artwork, once per upload, off the request path. Anthias polls the display
  # pages continuously; extracting there would decode the poster and write blob
  # metadata on every render (and had begun to, before this job).
  #
  # One at a time: libvips is memory-hungry and uploads arrive in bursts at the
  # start of a season, so serialise rather than stampede.
  class PaletteExtractionJob < ApplicationJob
    limits_concurrency key: "display_palette_extraction", duration: 5.minutes

    # ActiveStorage's AnalyzeJob saves the whole metadata hash from the copy it
    # loaded, so a palette written before it finishes is lost. Wait for it, five
    # minutes at most: a failed analysis never finishes.
    ANALYSIS_WAITS = 10

    def perform(event)
      blob = event.image&.blob
      return unless blob && event.uploaded_image?
      # An attach callback can fire for a blob the job already handled (a
      # re-save of the event); metadata presence, not the queue, is the ledger.
      return if blob.metadata.key?("palette_v2")
      return retry_job(wait: 30.seconds) if !blob.analyzed? && executions < ANALYSIS_WAITS

      Display::Palette.extract!(blob)
    end
  end
end
