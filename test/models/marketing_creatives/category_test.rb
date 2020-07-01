require 'test_helper'

class MarketingCreatives::CategoryTest < ActionView::TestCase
  setup do
    @category = FactoryBot.create(:marketing_creatives_category)
  end

  test 'missing image' do
    @category.image.purge
    @category.save(validate: false)

    assert_equal 'active_storage_default-missing.png', @category.fetch_image.filename.to_s
  end

  test 'to_param is url' do
    assert_equal @category.url, @category.to_param
  end
end
