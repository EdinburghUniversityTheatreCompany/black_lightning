module VideoLinkItem
  extend ActiveSupport::Concern

  included do
    has_many :video_links, class_name: '::VideoLink', as: :item
    accepts_nested_attributes_for :video_links, reject_if: :all_blank, allow_destroy: true
  end
end
