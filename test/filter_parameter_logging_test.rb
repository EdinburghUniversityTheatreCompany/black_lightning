require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "redacts reimbursements bank detail params from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter(sort_code: "12-34-56", account_number: "12345678",
                             sort_code_override: "20-00-00", account_number_override: "87654321",
                             description: "keep me")

    assert_equal ActiveSupport::ParameterFilter::FILTERED, filtered[:sort_code]
    assert_equal ActiveSupport::ParameterFilter::FILTERED, filtered[:account_number]
    assert_equal ActiveSupport::ParameterFilter::FILTERED, filtered[:sort_code_override]
    assert_equal ActiveSupport::ParameterFilter::FILTERED, filtered[:account_number_override]
    assert_equal "keep me", filtered[:description]
  end
end
