require "test_helper"

module Admin
  module Reimbursements
    ##
    # Bookmarks of the old year-nested URL land on the import, carrying their
    # year across as the selector param.
    class BudgetImportRoutingTest < ActionDispatch::IntegrationTest
      include ReimbursementsTestHelpers
      include Devise::Test::IntegrationHelpers

      setup do
        grant_finance_permission(users(:member))
        @year = ::Reimbursements::FinancialYear.create!(label: "Fringe 2027")
        sign_in users(:member)
      end

      test "the old year-nested URL redirects to the import carrying its year" do
        get "/admin/reimbursements/financial_years/#{@year.key}/budget_import"

        assert_redirected_to "/admin/reimbursements/budget_import?year=#{@year.key}"
        follow_redirect!
        assert_response :success
      end
    end
  end
end
