require 'test_helper'

class ArchivesControllerTest < ActionController::TestCase

  test "should get index" do
    get :index
    assert_response :success
  end

  test "should get index with date" do
    get :index, { :start_month => 01, :start_year => 1.years.ago.year, :end_month => 12, :end_year => Date.today.year }
    assert_response :success
  end

end
