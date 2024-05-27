require 'test_helper'

class Admin::AttachmentsControllerTest < ActionController::TestCase
  test 'should get index' do
    sign_in users(:admin)

    get :index

    assert_response :success
    assert_not_nil assigns(:attachments)

    assert_equal 'Attachments', assigns(:title)
  end

  test 'should ransack on attachment tags' do
    sign_in users(:admin)

    attachment_tag_id = AttachmentTag.all.first

    get :index, params: { q: { attachment_tags_id_eq: attachment_tag_id } }

    assert_response :success
    assert_not_nil assigns(:attachments)
  end
end
