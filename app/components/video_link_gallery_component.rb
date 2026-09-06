class VideoLinkGalleryComponent < ViewComponent::Base
  def initialize(video_links:, include_header: true)
    @video_links = video_links
    @include_header = include_header
  end

  private

  def any_video_links?
    @video_links.any?
  end
end
