module AttachmentsHelper
  include LinkHelper

  def get_url_for_attachment_item(attachment)
    namespace = get_namespace_for_link(attachment.item, true)

    return url_for([namespace, attachment.item])
  end
end