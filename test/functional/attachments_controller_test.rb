require 'test_helper'

class AttachmentsControllerTest < ActionController::TestCase
  test 'should get file' do
    eb = admin_editable_blocks(:public)
    FactoryBot.create(:attachment)
    attachment = FactoryBot.create(:attachment, editable_block: eb)

    get :file, params: { slug: attachment.name }

    assert_response :success

    assert_equal 'application/pdf', response.headers["Content-Type"]
    assert_equal "inline; test.pdf", response.headers["Content-Disposition"]
  end

  # Should not return a thumbnail, but just a file link.
  test 'should get pdf file as thumb' do
    eb = admin_editable_blocks(:public)
    FactoryBot.create(:attachment)
    attachment = FactoryBot.create(:attachment, editable_block: eb)

    get :file, params: { slug: attachment.name, style: 'ThUmb' }

    assert_response :success

    assert_equal 'application/pdf', response.headers["Content-Type"]
    assert_equal "inline; #{attachment.file.filename}", response.headers["Content-Disposition"]
  end

  test 'should get image file as thumb' do
    eb = admin_editable_blocks(:public)
    FactoryBot.create(:attachment)
    attachment = FactoryBot.create(:attachment, editable_block: eb)
    attachment.file.attach(io: File.open(Rails.root.join('test', 'test.png')), filename: 'test.png', content_type: 'image/png')

    assert attachment.file.image?

    get :file, params: { slug: attachment.name, style: :thumb }

    assert_response :success

    assert_equal 'image/png', response.headers["Content-Type"]
    assert_equal "inline; #{attachment.file.filename}", response.headers["Content-Disposition"]

    # It would be nice to check the dimensions of the response.
  end

  test 'should not get file for admin page when not signed in' do
    eb = admin_editable_blocks(:admin)
    attachment = FactoryBot.create(:attachment, editable_block: eb)

    get :file, params: { slug: attachment.name }

    assert_redirected_to access_denied_url
  end

  test 'should get file for admin page' do
    sign_in users(:admin)
    eb = admin_editable_blocks(:admin)
    attachment = FactoryBot.create(:attachment, editable_block: eb)

    get :file, params: { slug: attachment.name }
    assert_response :success
  end
end
