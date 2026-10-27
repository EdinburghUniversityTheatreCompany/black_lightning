namespace :display do
  desc "Extract ambient palettes for every current or future event's uploaded artwork (REALLY=1 to redo those already cached)"
  task backfill_palette: :environment do
    # key?("palette_v2"), not presence: an empty array (a colourless poster) and
    # false (a failed decode) are both answers, and neither is a reason to decode
    # again. REALLY=1 is the deliberate redo: it clears the key and re-extracts,
    # which is what changing the extraction needs.
    redo_all = ENV["REALLY"].present?

    Event.future.find_each do |event|
      blob = event.image&.blob
      next unless blob && event.uploaded_image?

      if blob.metadata.key?("palette_v2")
        next unless redo_all

        blob.update!(metadata: blob.metadata.except("palette_v2"))
      end

      Display::PaletteExtractionJob.perform_later(event)
      puts "queued #{event.name}"
    end
  end
end
