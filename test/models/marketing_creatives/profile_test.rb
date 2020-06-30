require 'test_helper'

class MarketingCreatives::ProfileTest < ActionView::TestCase
  test 'to_param is url' do
    @profile = FactoryBot.create(:marketing_creatives_profile)
    assert_equal @profile.url, @profile.to_param
  end
end
