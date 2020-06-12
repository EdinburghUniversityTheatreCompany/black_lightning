module ActiveStorageHelper
  # Please change the note in the assets/images/defaults folder if you change this.
  def default_image_blob(default_image_filename)
    prefix = 'active_storage_default'.freeze

    # Use a slash so user uploaded files are very unlikely to match.
    # It's not an issue if they do match, but it makes life harder when you want to replace the default image.
    key_filename = "#{prefix}/#{default_image_filename}"

    blob = ActiveStorage::Blob.find_by(filename: key_filename)

    if blob.nil?
      begin
        blob = ActiveStorage::Blob.create_after_upload!(
          io: File.open(Rails.root.join('app', 'assets', 'images', 'defaults', default_image_filename)),
          filename: key_filename, 
          content_type: 'image/png'  
        )
      rescue Errno::ENOENT => e
        raise ArgumentError, "There is no default file named #{default_image_filename} in the assets/images/defaults folder"
      end
    end
    
    return blob
  end

  def thumb_variant
    return { resize_to_fill: [192, 100] }
  end

  def slideshow_variant
    return { resize_to_fill: [960, 500] }
  end

  def square_thumb_variant
    return { resize_to_fill: [150, 150] }
  end

  def square_display_variant
    return { resize_to_fill: [700, 700] }
  end
end
