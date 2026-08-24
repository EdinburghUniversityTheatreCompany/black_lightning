require "test_helper"

##
# Deleting an account is how a GDPR erasure request is served here, so it has
# to reach the bank details the account was linked to. Nothing else did: the
# link is a nullifying belongs_to and PersonLink re-matches by email, so before
# this the sort code and account number simply stayed.
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

  # The claims are the society's financial records and the payee row is what
  # they hang off, so they outlive the account. Erasure takes the bank details,
  # which have no such obligation behind them.
  test "the payee and their claims survive the account being deleted" do
    expense = create_reimbursements_expense(person: @person, status: Reimbursements::Status::PAID)

    @user.destroy!

    assert Reimbursements::Person.exists?(@person.id)
    assert_equal @person.id, expense.reload.person_id
  end

  test "deleting a user with no linked payee is untroubled by it" do
    plain = FactoryBot.create(:user, email: "unlinked@example.com")

    assert_nothing_raised { plain.destroy! }
  end

  # The link is by email as well as by the stored id, so a payee that was never
  # id-linked must still be reached — otherwise erasure quietly misses the very
  # people who have claimed least recently.
  test "an email-matched payee is erased even without a stored link" do
    user = FactoryBot.create(:user, email: "matched@example.com")
    person = create_reimbursements_person(name: "Matched May", email: user.email,
                                          sort_code: "08-99-99", account_number: "66374958")

    user.destroy!

    assert_nil person.reload.payment_details
  end
end
