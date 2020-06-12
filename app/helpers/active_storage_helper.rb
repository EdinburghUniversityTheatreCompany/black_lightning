module ActiveStorageHelper
  # Please change the note in the assets/images/defaults folder if you change this.
  def default_image_blob(default_image_filename)
    prefix = 'active_storage_default'.freeze
    key_filename = "#{prefix}-#{default_image_filename}"
    blob = ActiveStorage::Blob.find_by(filename: key_filename)

    if blob.nil?
      blob = ActiveStorage::Blob.create_after_upload!(
        io: File.open(Rails.root.join('app', 'assets', 'images', 'defaults', default_image_filename)),
        filename: key_filename, 
        content_type: 'image/png'  
      )
    end
    
    return blob
  end

  def thumb_variant
    return { resize_to_fill: [192, 100] }
  end

  def slideshow_variant
    return { resize_to_fill: [960, 500] }
  end
end
