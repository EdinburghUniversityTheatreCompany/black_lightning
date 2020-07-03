# == Schema Information
#
# Table name: marketing_creatives_categories
#
# *id*::              <tt>bigint, not null, primary key</tt>
# *name*::            <tt>string(255)</tt>
# *name_on_profile*:: <tt>string(255)</tt>
# *url*::             <tt>string(255)</tt>
# *created_at*::      <tt>datetime, not null</tt>
# *updated_at*::      <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
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
