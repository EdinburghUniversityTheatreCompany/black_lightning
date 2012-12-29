require 'test_helper'
require 'rails/performance_test_help'

class BrowsingTest < ActionDispatch::PerformanceTest
  # Refer to the documentation for all available options
  self.profile_options = { :runs => 5 }

  def setup
    FactoryGirl.create_list(:show, 10)
  end

  def test_homepage
    get '/'
  end
end
