# https://edgeguides.rubyonrails.org/active_storage_overview.html#purging-unattached-uploads

namespace :active_storage do
  desc "Purges unattached Active Storage blobs. Run regularly."
  task purge_unattached: :environment do
    ActiveStorage::Blob.unattached.where("active_storage_blobs.created_at <= ?", 2.days.ago).find_each(&:purge_later)
  end

  desc "Find corrupted image blobs (migration errors, invalid files)"
  task validate_blobs: :environment do
    image_content_types = %w[image/png image/jpeg image/gif image/webp]

    puts "Checking image blobs..."

    # Phase 1: Quick check for suspiciously small "images" (likely JSON/text errors)
    tiny_blobs = ActiveStorage::Blob
      .where(content_type: image_content_types)
      .where("byte_size < 500")
      .pluck(:id, :byte_size, :filename)

    puts "\n=== Suspiciously small blobs (<500 bytes) ==="
    tiny_blobs.each do |id, size, filename|
      puts "  ID: #{id}, Size: #{size} bytes, Filename: #{filename}"
    end
    puts "Total: #{tiny_blobs.count}"

    # Phase 2: Try processing each image blob with vips
    corrupted = []
    ActiveStorage::Blob.where(content_type: image_content_types).find_each do |blob|
      print "."
      blob.open do |file|
        Vips::Image.new_from_file(file.path)
      end
    rescue Vips::Error => e
      corrupted << { id: blob.id, byte_size: blob.byte_size, filename: blob.filename.to_s, error: e.message }
      print "X"
    rescue => e
      corrupted << { id: blob.id, byte_size: blob.byte_size, filename: blob.filename.to_s, error: "#{e.class}: #{e.message}" }
      print "!"
    end

    puts "\n\n=== Blobs that fail vips processing ==="
    corrupted.each do |blob|
      puts "  ID: #{blob[:id]}, Size: #{blob[:byte_size]} bytes, Filename: #{blob[:filename]}"
      puts "    Error: #{blob[:error]}"
    end
    puts "Total: #{corrupted.count}"
  end

  desc "Restore corrupted blobs from original Paperclip folder"
  task :restore_from_paperclip, [ :paperclip_path ] => :environment do |t, args|
    paperclip_root = args[:paperclip_path]
    unless paperclip_root
      puts "Usage: rake 'active_storage:restore_from_paperclip[/path/to/public/system]'"
      exit 1
    end

    # Map of model -> Paperclip attachment config
    attachment_config = {
      "Picture" => { attachment: "images", column: "image_file_name" },
      "Event" => { attachment: "images", column: "image_file_name" },
      "News" => { attachment: "images", column: "image_file_name" },
      "Venue" => { attachment: "images", column: "image_file_name" },
      "User" => { attachment: "avatars", column: "avatar_file_name" },
      "Attachment" => { attachment: "files", column: "file_file_name" }
    }

    # Find corrupted blobs (small byte_size = likely JSON error responses)
    corrupted_blobs = ActiveStorage::Blob
      .joins("INNER JOIN active_storage_attachments ON active_storage_attachments.blob_id = active_storage_blobs.id")
      .where("active_storage_blobs.byte_size < 500")
      .where("active_storage_blobs.content_type LIKE 'image/%'")
      .select("active_storage_blobs.*, active_storage_attachments.record_type, active_storage_attachments.record_id, active_storage_attachments.name")

    restored = 0
    failed = 0

    corrupted_blobs.each do |blob|
      record_type = blob.record_type
      record_id = blob.record_id
      config = attachment_config[record_type]

      unless config
        puts "SKIP: Unknown record type #{record_type}"
        failed += 1
        next
      end

      # Get original filename from the model's Paperclip column
      record = record_type.constantize.find_by(id: record_id)
      unless record
        puts "SKIP: #{record_type} ##{record_id} not found"
        failed += 1
        next
      end

      original_filename = record.send(config[:column])
      unless original_filename
        puts "SKIP: #{record_type} ##{record_id} has no #{config[:column]}"
        failed += 1
        next
      end

      # Build Paperclip path: /system/:class/:attachment/:id_partition/:style/:filename
      id_partition = "%09d" % record_id
      id_partition = "#{id_partition[0, 3]}/#{id_partition[3, 3]}/#{id_partition[6, 3]}"

      paperclip_path = File.join(
        paperclip_root,
        record_type.underscore.pluralize,
        config[:attachment],
        id_partition,
        "original",
        original_filename
      )

      unless File.exist?(paperclip_path)
        puts "SKIP: File not found at #{paperclip_path}"
        failed += 1
        next
      end

      # Re-upload the file
      blob.upload(File.open(paperclip_path))
      blob.update!(byte_size: File.size(paperclip_path))
      puts "RESTORED: Blob #{blob.id} from #{paperclip_path}"
      restored += 1
    end

    puts "\n=== Summary ==="
    puts "Restored: #{restored}"
    puts "Failed: #{failed}"
  end
end
