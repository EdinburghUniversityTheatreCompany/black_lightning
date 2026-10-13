require "test_helper"

module Admin
  module Reimbursements
    ##
    # The two gates every FinanceController page inherits, proved once here instead of in each
    # controller's test: sign-in (AdminController) and `:manage, :reimbursements_finance`
    # (FinanceController#authorize_finance!). The gate answers before the action runs, so the
    # table needs no data. Nominal codes are write-only and keep their own tests.
    class FinanceGateTest < ActionDispatch::IntegrationTest
      include ReimbursementsTestHelpers
      include Devise::Test::IntegrationHelpers

      # One parameter-free GET per finance controller.
      def finance_paths
        [ admin_reimbursements_actuals_path, admin_reimbursements_batches_path,
          admin_reimbursements_budget_import_path, admin_reimbursements_budgets_path,
          admin_reimbursements_expense_edits_path, admin_reimbursements_expense_import_path,
          admin_reimbursements_export_path, download_admin_reimbursements_export_path,
          admin_reimbursements_financial_years_path, admin_reimbursements_people_path,
          admin_reimbursements_reconciliation_path, admin_reimbursements_review_path,
          admin_reimbursements_settings_path, admin_reimbursements_status_path ]
      end

      # The producer portal's pages answer to the base permission instead.
      def portal_paths
        [ admin_reimbursements_expenses_path, admin_reimbursements_my_budgets_path,
          admin_reimbursements_glossary_path ]
      end

      test "a signed-out visitor is sent to sign in on every finance page" do
        finance_paths.each do |path|
          get path

          assert_redirected_to new_user_session_path, path
        end
      end

      test "a signed-out visitor is sent to sign in on every producer portal page" do
        portal_paths.each do |path|
          get path

          assert_redirected_to new_user_session_path, path
        end
      end

      test "a member without the finance permission is refused every finance page" do
        sign_in users(:committee)

        finance_paths.each do |path|
          get path

          assert_response :forbidden, path
        end
      end

      test "the producer portal permission alone does not grant finance access" do
        submitter = users(:member_with_phone_number)
        grant_producer_permission(submitter)
        sign_in submitter

        finance_paths.each do |path|
          get path

          assert_response :forbidden, path
        end
      end
    end
  end
end
