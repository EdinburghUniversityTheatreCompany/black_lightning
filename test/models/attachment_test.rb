require 'test_helper'

class AttachmentTest < ActionView::TestCase
  test 'slug' do
    attachment = FactoryBot.create(:attachment)
    assert_equal attachment.name, attachment.slug
  end

  test 'thumb' do
    attachment = FactoryBot.create(:attachment, name: 'Bedlam Bear')
    attachment.file = fixture_file_upload(Rails.root.join('test', 'test.png'), 'image')

    assert_match '/attachments/Bedlam%20Bear/thumb', attachment.file.url(:thumb)
  end
end
