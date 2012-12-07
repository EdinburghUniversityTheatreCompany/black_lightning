require 'test_helper'

class Archives::ShowsControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_redirected_to archives_shows_index_path(01, 1.years.ago.year, 12, Date.today.year)
  end

  test "should get index with date" do
    get :index, { :start_month => 1, :start_year => 1.years.ago.year, :end_month => 12, :end_year => Date.today.year }
    assert_response :success
  end
end
