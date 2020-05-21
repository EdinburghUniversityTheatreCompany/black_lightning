require 'test_helper'

class AttachmentsControllerTest < ActionController::TestCase
  test 'should get show' do
    eb = admin_editable_blocks(:public)
    attachment = FactoryBot.create(:attachment, editable_block: eb)

    get :show, params: { slug: attachment.name }
    assert_response :success
  end

  test 'should get show for admin page' do
    sign_in users(:admin)
    eb = admin_editable_blocks(:admin)
    attachment = FactoryBot.create(:attachment, editable_block: eb)

    get :show, params: { slug: attachment.name }
    assert_response :success
  end
end
