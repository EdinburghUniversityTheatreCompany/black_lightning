module ActiveStorageHelper
  def thumb_variant
    return { resize_to_fit: '192x100' }
  end

  def slideshow_variant
    return { resize_to_fit: '960x500' }
  end
end
