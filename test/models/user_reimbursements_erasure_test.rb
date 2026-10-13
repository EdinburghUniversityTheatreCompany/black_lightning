require "test_helper"

##
# Deleting an account serves a GDPR erasure request, so it must reach the bank
# details the account was linked to.
class UserReimbursementsErasureTest < ActiveSupport::TestCase
  include ReimbursementsTestHelpers

  setup do
    @user = FactoryBot.create(:user, email: "leaving@example.com")
    @person = create_reimbursements_person(name: "Leaving Lee", email: @user.email,
                                           sort_code: "08-99-99", account_number: "66374958")
    @user.update!(reimbursements_person: @person)
  end

  test "deleting a user destroys the bank details of the payee it was linked to" do
    assert @person.payment_details.present?

    @user.destroy!

    assert_nil @person.reload.payment_details
    assert_equal "", @person.account_number
  end

  # Claims are financial records and hang off the payee row, so they outlive the account.
  test "the payee and their claims survive the account being deleted" do
    expense = create_reimbursements_expense(person: @person, status: Reimbursements::Status::PAID)

    @user.destroy!

    assert Reimbursements::Person.exists?(@person.id)
    assert_equal @person.id, expense.reload.person_id
  end

  # The link is by email as well as stored id, or erasure would miss never-linked payees.
  test "an email-matched payee is erased even without a stored link" do
    user = FactoryBot.create(:user, email: "matched@example.com")
    person = create_reimbursements_person(name: "Matched May", email: user.email,
                                          sort_code: "08-99-99", account_number: "66374958")

    user.destroy!

    assert_nil person.reload.payment_details
  end
end
