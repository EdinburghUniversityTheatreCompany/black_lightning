# == Schema Information
#
# Table name: marketing_creatives_category_infos
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *profile_id*::  <tt>bigint</tt>
# *category_id*:: <tt>bigint</tt>
# *description*:: <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class MarketingCreatives::CategoryInfoTest < ActionView::TestCase
  setup do
    @category_info = FactoryBot.create(:marketing_creatives_category_info)
  end

  test 'missing image' do
    @category_info.image.purge
    @category_info.save(validate: false)

    assert_equal 'active_storage_default-missing.png', @category_info.fetch_image.filename.to_s
  end
end
