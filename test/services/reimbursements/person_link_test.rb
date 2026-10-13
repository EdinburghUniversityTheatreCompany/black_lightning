require "test_helper"

module Reimbursements
  class PersonLinkTest < ActiveSupport::TestCase
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
    end

    test "database backend person_for returns nil when unmatched" do
      assert_nil PersonLink.new(store: DatabaseStore.new).person_for(users(:user))
    end

    # The stored FK is a HINT: when its row is gone, person_for falls through to the
    # email match and rewrites it, or the next submission mints a SECOND payee with
    # no bank details. Unreachable in-app (real FK plus dependent: :nullify), so it
    # defends against a restore or script run with FOREIGN_KEY_CHECKS off; reproduce
    # it with referential integrity disabled for the delete only.
    def orphan_the_stored_link!(user)
      person = Reimbursements::Person.create!(name: "Gone", email: "gone@example.com")
      user.update_column(:reimbursements_person_id, person.id)
      Person.connection.disable_referential_integrity do
        Person.connection.delete("DELETE FROM #{Person.table_name} WHERE id = #{person.id.to_i}")
      end
      assert_equal person.id, user.reload.reimbursements_person_id, "the FK really is dangling"
      assert_nil Person.find_by(id: person.id)
      person.id
    end

    test "database backend falls back to the email match behind a dangling FK without creating a duplicate payee" do
      user = users(:user)
      orphan_the_stored_link!(user)
      current = Reimbursements::Person.create!(name: "Current", email: user.email)

      link = PersonLink.new(store: DatabaseStore.new)

      assert_no_difference -> { Reimbursements::Person.count } do
        assert_equal current.id, link.ensure_person!(user).id, "the dangling FK must not win"
      end
      assert_equal current.id, user.reload.reimbursements_person_id, "the stale FK is rewritten"
    end
  end
end
