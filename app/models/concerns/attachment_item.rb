module AttachmentItem
  extend ActiveSupport::Concern

  included do
    has_many :attachments, -> { includes(:attachment_tags, :attachment_tags_attachments, { file_attachment: :blob }) },
             class_name: '::Attachment', as: :item
    accepts_nested_attributes_for :attachments, reject_if: :all_blank, allow_destroy: true
  end
end
