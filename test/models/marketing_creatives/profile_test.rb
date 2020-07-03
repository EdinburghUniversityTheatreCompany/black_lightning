# == Schema Information
#
# Table name: marketing_creatives_profiles
#
# *id*::         <tt>bigint, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *url*::        <tt>string(255)</tt>
# *about*::      <tt>text(65535)</tt>
# *approved*::   <tt>boolean</tt>
# *user_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require 'test_helper'

class MarketingCreatives::ProfileTest < ActionView::TestCase
  test 'to_param is url' do
    @profile = FactoryBot.create(:marketing_creatives_profile)
    assert_equal @profile.url, @profile.to_param
  end
end
