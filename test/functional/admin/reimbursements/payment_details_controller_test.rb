require "test_helper"

module Admin
  module Reimbursements
  class PaymentDetailsControllerTest < ActionController::TestCase
    include ReimbursementsTestHelpers

    setup do
      producer = Role.create!(name: "Producer")
      producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
      users(:member).add_role("Producer")
      users(:member_with_phone_number).add_role("Producer")
      @user = users(:member)
      @store, @client = build_fake_store(people: [ airtable_person_record(email: @user.email) ])
      BaseController.store_builder = -> { @store }
      sign_in @user
    end

    teardown do
      BaseController.store_builder = -> { ::Reimbursements::Store.new }
    end

    test "edit prefills from the linked person" do
      get :edit
      assert_response :success
      assert_includes response.body, "Pat Producer"
    end

    test "update writes normalized details to the people table" do
      patch :update, params: {
        reimbursements_payment_details_form: {
          name: "Pat Producer", sort_code: "80-22-60", account_number: "1234 5678"
        }
      }

      assert_redirected_to admin_reimbursements_expenses_path
      table, record_id, fields = @client.updated.sole
      assert_equal :people, table
      assert_equal "recPer1", record_id
      assert_equal "80-22-60", fields[ReimbursementsTestHelpers::FIELD_IDS[:people][:sort_code]],
                   "sort codes are stored in the conventional dashed form"
      assert_equal "12345678", fields[ReimbursementsTestHelpers::FIELD_IDS[:people][:account_number]]
    end

    test "update creates the people record for unmatched users" do
      other = users(:member_with_phone_number)
      sign_in other

      patch :update, params: {
        reimbursements_payment_details_form: {
          name: "Mem Ber", sort_code: "112233", account_number: "12345678"
        }
      }

      assert_redirected_to admin_reimbursements_expenses_path
      assert_equal 1, @client.created.size
      assert_equal "recNew1", other.reload.airtable_person_id
    end

    test "invalid input re-renders with errors" do
      patch :update, params: {
        reimbursements_payment_details_form: { name: "", sort_code: "80", account_number: "1" }
      }

      assert_response :unprocessable_entity
      assert_empty @client.updated
    end
  end
  end
end
