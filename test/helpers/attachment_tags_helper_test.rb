require "test_helper"

class AttachmentTagsHelperTest < ActionView::TestCase
  test "get_link_to_attachments_for_tag" do
    attachment_tag = attachment_tags(:rigplan)

    result = get_link_to_attachments_for_tag(attachment_tag)
    assert_includes result, "View Attachments"
    assert_includes result, "/admin/attachments?q%5Battachment_tags_id_eq%5D=#{attachment_tag.id}"
    assert_includes result, ButtonComponent.classes_for(variant: :secondary).split.first
  end
end
