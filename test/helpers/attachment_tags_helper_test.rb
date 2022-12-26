require 'test_helper'

class AttachmentTagsHelperTest < ActionView::TestCase
  test 'get_link_to_attachments_for_tag' do
    attachment_tag = attachment_tags(:rigplan)

    assert_equal "<a class=\"btn btn-secondary\" href=\"/admin/attachments?q%5Battachment_tags_id_eq%5D=#{attachment_tag.id}\">View Attachments</a>", get_link_to_attachments_for_tag(attachment_tag)
  end
end
