require "test_helper"

module Reimbursements
  class PersonLinkTest < ActiveSupport::TestCase
    # PersonLink runs against the DatabaseStore (the only backend): the stored
    # link is the real reimbursements_person_id FK.

    test "database backend resolves and persists the FK link" do
      user = users(:user)
      person = Reimbursements::Person.create!(name: "Pat", email: user.email)
      link = PersonLink.new(store: DatabaseStore.new)

      assert_equal person.id, link.person_for(user).id
      assert_equal person.id, user.reload.reimbursements_person_id
    end

    test "database backend prefers the stored FK over an email match" do
      user = users(:user)
      linked = Reimbursements::Person.create!(name: "Linked", email: "other@example.com")
      Reimbursements::Person.create!(name: "Email Match", email: user.email)
      user.update_column(:reimbursements_person_id, linked.id)

      link = PersonLink.new(store: DatabaseStore.new)
      assert_equal linked.id, link.person_for(user).id
    end

    test "database backend creates the payee on first submission" do
      user = users(:user)
      link = PersonLink.new(store: DatabaseStore.new)

      person = link.ensure_person!(user)
      assert_equal user.email, person.email
      assert_equal person.id, user.reload.reimbursements_person_id
      assert_nil user.airtable_person_id
    end

    test "database backend person_for returns nil when unmatched" do
      assert_nil PersonLink.new(store: DatabaseStore.new).person_for(users(:user))
    end
  end
end
