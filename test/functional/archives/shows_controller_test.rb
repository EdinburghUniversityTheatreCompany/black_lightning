require 'test_helper'

class Archives::ShowsControllerTest < ActionController::TestCase
  test "should get index" do
    get :index
    assert_redirected_to archives_shows_index_path(01, 1.years.ago.year, 12, Date.today.year)
  end
end
