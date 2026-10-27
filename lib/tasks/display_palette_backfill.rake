namespace :display do
  desc "Extract ambient palettes for every current or future event's uploaded artwork"
  task backfill_palette: :environment do
    Event.future.find_each do |event|
      blob = event.image&.blob
      next unless blob && event.uploaded_image?
      next if blob.metadata.key?("palette_v2")

      Display::PaletteExtractionJob.perform_later(event)
      puts "queued #{event.name}"
    end
  end
end
