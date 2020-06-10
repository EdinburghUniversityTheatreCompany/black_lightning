module ActiveStorageHelper
  def thumb_variant
    return { resize: '192x100' }
  end

  def slideshow_variant
    return { resize: '960x500' }
  end
end
