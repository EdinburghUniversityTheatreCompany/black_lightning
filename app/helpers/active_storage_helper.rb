module ActiveStorageHelper
  # Please change the note in the assets/images/defaults folder if you change this or the key_filename.
  PREFIX = 'active_storage_default'.freeze

  def default_image_blob(default_image_filename)
    # Use a slash so user uploaded files are very unlikely to match.
    # It's not an issue if they do match, but it makes life a little bit harder when you want to replace the default image.
    key_filename = "#{PREFIX}/#{default_image_filename}"

    blob = ActiveStorage::Blob.find_by(filename: key_filename)

    if blob.nil?
      begin
        blob = ActiveStorage::Blob.create_and_upload!(
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

  def get_file_attached_hint(file)
    # nil because the message next to the button also displays 'No file chosen'
    if file.attached?
      filename = file.filename.to_s

      return "Current file: #{link_to filename, url_for(file)}".html_safe unless filename.starts_with?(PREFIX) 
    end
  end

  # BOOTSTRAP NICETOHAVE: Look into the apropriateness of these dimensions.
  def thumb_variant(scale_factor = 1)
    return { resize_to_fill: [192 * scale_factor, 100 * scale_factor] }
  end

  def thumb_variant_public(scale_factor = 1)
    return thumb_variant(1.5 * scale_factor)
  end

  def medium_variant
    return { resize_to_fill: [576, 300] }
  end

  def slideshow_variant
    return { resize_to_fill: [960, 500] }
  end

  def square_thumb_variant(dimensions = 150)
    return { resize_to_fill: [dimensions, dimensions] }
  end

  def square_display_variant
    return { resize_to_fill: [700, 700] }
  end

  def variant_width_and_height_html(variant)
    return { width: variant[:resize_to_fill][0], height: variant[:resize_to_fill][1] }
  end

  def base_width_and_height_html(image)
    return { width: image.metadata['width'], height: image.metadata['height'] }
  end
end
