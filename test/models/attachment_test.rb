require 'test_helper'

class AttachmentTest < ActionView::TestCase
  test 'slug' do
    attachment = FactoryBot.create(:attachment)
    assert_equal attachment.name, attachment.slug
  end
end
