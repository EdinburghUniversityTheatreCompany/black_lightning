require 'test_helper'

class AttachmentTest < ActionView::TestCase
  setup do
    @attachment = FactoryBot.create(:attachment)
  end
  
  test 'slug' do
    assert_equal @attachment.name, @attachment.slug
  end
end
