require 'test_helper'

class AttachmentsHelperTest < ActionView::TestCase
  test 'get link for editable block' do
    editable_block_attachment = FactoryBot.create(:editable_block_attachment)

    assert_equal "/admin/editable_blocks/#{editable_block_attachment.item.id}", get_url_for_attachment_item(editable_block_attachment)
  end

  test 'get link for show' do
    show_attachment = FactoryBot.create(:show_attachment)

    assert_equal "/admin/shows/#{show_attachment.item.slug}", get_url_for_attachment_item(show_attachment)
  end

  test 'get link for answer' do
    attachment = FactoryBot.create(:answer_attachment)

    assert attachment.item.answerable.is_a?(Admin::Questionnaires::Questionnaire)
    assert_equal "/admin/questionnaires/questionnaires/#{attachment.item.answerable.id}", get_url_for_attachment_item(attachment)
  end
end
