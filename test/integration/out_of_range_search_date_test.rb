require "test_helper"

# A date input accepts a five-digit year, which MySQL refuses as a DATE: the search used to 500.
class OutOfRangeSearchDateTest < ActionDispatch::IntegrationTest
  test "a five-digit year in a search date is ignored, not a 500" do
    get "/archives/shows", params: { q: { author_cont: "Chekhov", end_date_gteq: "11988-10-01", start_date_lteq: "" } }

    assert_response :success
  end

  test "date inputs refuse a year past 9999 in the browser" do
    get "/archives/shows"

    assert_select "input[type=date][name='q[end_date_gteq]'][max='9999-12-31']"
    assert_select "input[type=date][name='q[start_date_lteq]'][max='9999-12-31']"
  end
end
