require 'test_helper'

class AttachmentsControllerTest < ActionController::TestCase
  setup do
    @editable_block = admin_editable_blocks(:public)
  end

  test 'should get file' do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)

    get :file, params: { slug: attachment.name }

    assert_response :success

    assert_equal 'application/pdf', response.headers["Content-Type"]
    assert_equal "inline; test.pdf", response.headers["Content-Disposition"]
  end

  # Should not return a thumbnail, but just a file link.
  test 'should get pdf file as thumb' do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)

    get :file, params: { slug: attachment.name, style: 'ThUmb' }

    assert_response :success

    assert_equal 'application/pdf', response.headers["Content-Type"]
    assert_equal "inline; #{attachment.file.filename}", response.headers["Content-Disposition"]
  end

  test 'should get image file as thumb' do
    attachment = FactoryBot.create(:attachment, item: @editable_block, access_level: 2)
    attachment.file.attach(io: File.open(Rails.root.join('test', 'test.png')), filename: 'test.png', content_type: 'image/png')

    assert attachment.file.image?

    get :file, params: { slug: attachment.name, style: :thumb }

    assert_response :success

    assert_equal 'image/png', response.headers["Content-Type"]
    assert_equal "inline; #{attachment.file.filename}", response.headers["Content-Disposition"]

    # It would be nice to check the dimensions of the response.
  end

  test 'should not get file for admin page editable_block when not signed in' do
    admin_editable_block = admin_editable_blocks(:admin)
    attachment = FactoryBot.create(:attachment, item: admin_editable_block, access_level: 2)

    get :file, params: { slug: attachment.name }

    assert_response 403
  end

  test 'should get file for admin page editable_block when signed in as admin' do
    sign_in users(:admin)
    admin_editable_block = admin_editable_blocks(:admin)
    attachment = FactoryBot.create(:attachment, item: admin_editable_block)

    get :file, params: { slug: attachment.name }
    assert_response :success
  end
end
