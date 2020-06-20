class Tasks::Logic::Migrations
  def self.fix_editing_deadline
    counter = 0
    Admin::Proposals::Call.all.each do |call|
      next if call.editing_deadline.present?

      call.update_attribute(:editing_deadline, call.submission_deadline)
      counter += 1
    end

    return counter
  end

  # :nocov:
  def self.venue_image
    model = Venue
    attachments = ['image']

    migrate_from_paperclip_to_active_storage(model, attachments)
  end

  def self.migrate_from_paperclip_to_active_storage(model, attachments)
    model.find_each.each do |instance|
      attachments.each do |attachment|
        if instance.send(attachment).path.blank?
          next
        elsif !File.file?(instance.send(attachment).path)
          p "WARNING: #{instance.send(attachment).path} does not exist on disk."
          next
        end

        p "Migrating #{attachment} for #{instance}"

        begin
          blob = ActiveStorage::Blob.create(
            key: key(instance, attachment),
            filename: instance.send("#{attachment}_file_name"),
            content_type: instance.send("#{attachment}_content_type"),
            byte_size: instance.send("#{attachment}_file_size"),
            checksum: checksum(instance.send(attachment)),
            created_at: instance.updated_at.iso8601
          )

          self.copy_file_from_paperclip_to_storage(attachment, blob, instance)

          ActiveStorage::Attachment.create(
            name: attachment, 
            record_type: model.name, 
            record_id: instance.id, 
            blob_id: blob.id, 
            created_at: instance.updated_at.iso8601
          )
        end
      rescue => e
        p "FAILED for name #{instance.send("#{attachment}_file_name")} with ID #{instance.id}"
        p e
      end
    end
  end

  private
  
  def self.key(instance, attachment)
    SecureRandom.uuid
  end

  def self.checksum(attachment)
    # local files stored on disk:
    url = attachment.path
    Digest::MD5.base64digest(File.read(url))
  end

  def self.copy_file_from_paperclip_to_storage(name, blob, instance)
    # Example: Gets the image from the Venue Bedlam Theatre
    source = instance.send(name).path

    destination_directory = File.join(
      "storage",
      blob.key.first(2),
      blob.key.first(4).last(2)
    )

    destination = File.join(destination_directory, blob.key)
  
    FileUtils.mkdir_p(destination_directory)
    puts "Copying #{source} to #{destination}"
    FileUtils.cp(source, destination)
  end
  # :nocov:
end
