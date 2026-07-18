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
      @person = create_reimbursements_person(email: @user.email)
      sign_in @user
    end

    test "edit prefills from the linked person" do
      get :edit
      assert_response :success
      assert_includes response.body, "Pat Producer"
    end

    test "update writes normalized details to the payment details record" do
      patch :update, params: {
        reimbursements_payment_details_form: {
          name: "Pat Producer", sort_code: "80-22-60", account_number: "1234 5678"
        }
      }

      assert_redirected_to admin_reimbursements_expenses_path
      details = @person.reload.payment_details
      assert_equal "80-22-60", details.sort_code,
                   "sort codes are stored in the conventional dashed form"
      assert_equal "12345678", details.account_number
    end

    test "update creates the people record for unmatched users" do
      other = users(:member_with_phone_number)
      sign_in other

      assert_difference -> { ::Reimbursements::Person.count }, 1 do
        patch :update, params: {
          reimbursements_payment_details_form: {
            name: "Mem Ber", sort_code: "112233", account_number: "12345678"
          }
        }
      end

      assert_redirected_to admin_reimbursements_expenses_path
      created = ::Reimbursements::Person.find_by!(email: other.email)
      assert_equal created.id, other.reload.reimbursements_person_id
    end

    test "invalid input re-renders with errors" do
      patch :update, params: {
        reimbursements_payment_details_form: { name: "", sort_code: "80", account_number: "1" }
      }

      assert_response :unprocessable_entity
      assert_nil @person.reload.payment_details
    end
  end
  end
end
