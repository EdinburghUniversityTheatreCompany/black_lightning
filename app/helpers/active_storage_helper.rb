module ActiveStorageHelper
  def thumb_variant
    return { resize_to_fill: [192, 100] }
  end

  def slideshow_variant
    return { resize_to_fill: [960, 500] }
  end
end
