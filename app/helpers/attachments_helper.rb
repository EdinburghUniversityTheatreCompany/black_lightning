module AttachmentsHelper
  include LinkHelper

  def get_url_for_attachment_item(attachment)
    if attachment.item_type == "Admin::Answer"
      url_for(attachment.item.answerable)
    else
      namespace = get_namespace_for_link(attachment.item, true)

      url_for([ namespace, attachment.item ])
    end
  end
end
