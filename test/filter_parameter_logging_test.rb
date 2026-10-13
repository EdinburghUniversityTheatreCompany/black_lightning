require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "redacts reimbursements bank detail params from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    redacted = ActiveSupport::ParameterFilter::FILTERED

    assert_equal({ sort_code: redacted, account_number: redacted, sort_code_override: redacted,
                   account_number_override: redacted, description: "keep me" },
                 filter.filter(sort_code: "12-34-56", account_number: "12345678",
                               sort_code_override: "20-00-00", account_number_override: "87654321",
                               description: "keep me"))
  end
end
