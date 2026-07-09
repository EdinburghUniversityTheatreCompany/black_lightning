require "test_helper"

module Admin
  module Reimbursements
    class ReceiptsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      TWO_RECEIPTS = [
        { "id" => "att1", "filename" => "old.pdf", "url" => "https://x", "size" => 1, "type" => "application/pdf" },
        { "id" => "att2", "filename" => "new.pdf", "url" => "https://y", "size" => 1, "type" => "application/pdf" }
      ].freeze

      setup do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        users(:member).add_role("Producer")
        @user = users(:member)
        @store, @client = build_fake_store(
          expenses: [ airtable_expense_record(receipts: TWO_RECEIPTS.map(&:dup)),
                      airtable_expense_record(id: "recExpOther", payee_id: "recPerOther", receipts: TWO_RECEIPTS.map(&:dup)) ],
          people: [ airtable_person_record(email: @user.email),
                    airtable_person_record(id: "recPerOther", email: "other@example.com") ],
          budgets: [ airtable_budget_record ]
        )
        BaseController.store_builder = -> { @store }
        sign_in @user
      end

      teardown do
        BaseController.store_builder = -> { ::Reimbursements::Store.new }
      end

      test "removes a receipt from an own pending expense" do
        delete :destroy, params: { expense_id: "recExp1", id: "att1" }

        assert_redirected_to edit_admin_reimbursements_expense_path("recExp1")
        _table, record_id, fields = @client.updated.sole
        assert_equal "recExp1", record_id
        assert_equal [ { "id" => "att2" } ], fields[ReimbursementsTestHelpers::FIELD_IDS[:expenses][:receipt]]
      end

      test "refuses to remove the last receipt" do
        one_receipt = [ TWO_RECEIPTS.first.dup ]
        @store, @client = build_fake_store(
          expenses: [ airtable_expense_record(receipts: one_receipt) ],
          people: [ airtable_person_record(email: @user.email) ],
          budgets: [ airtable_budget_record ]
        )
        BaseController.store_builder = -> { @store }

        delete :destroy, params: { expense_id: "recExp1", id: "att1" }

        assert_redirected_to edit_admin_reimbursements_expense_path("recExp1")
        assert_match(/last receipt/, flash[:alert])
        assert_empty @client.updated
      end

      test "404s for another person's expense" do
        delete :destroy, params: { expense_id: "recExpOther", id: "att1" }

        assert_response :not_found
        assert_empty @client.updated
      end
    end
  end
end
