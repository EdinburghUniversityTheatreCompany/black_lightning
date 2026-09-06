class VideoLinkGalleryComponentPreview < ViewComponent::Preview
  def default
    render VideoLinkGalleryComponent.new(video_links: VideoLink.limit(2))
  end

  # Inside a show page's field list, where the surrounding row supplies the heading.
  def without_header
    render VideoLinkGalleryComponent.new(video_links: VideoLink.limit(2), include_header: false)
  end

  def empty
    render VideoLinkGalleryComponent.new(video_links: VideoLink.none)
  end
end
