module AttachmentTagsHelper
  def get_link_to_attachments_for_tag(attachment_tag)
    link_to("View Attachments", admin_attachments_path("q[attachment_tags_id_eq]" => attachment_tag.id), { class: "btn btn-secondary" })
  end
end
