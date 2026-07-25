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

    # --- Stale stored link (recovery branch) -------------------------------
    # The stored FK is a HINT, not a verdict: person_for looks the payee up and,
    # when the row is gone, falls THROUGH to the email match and rewrites the FK.
    # Without that fall-through the user resolves to no payee at all and their
    # next submission mints a SECOND payee row for the same person — two payees,
    # one of them with no bank details, and a producer who never gets paid.
    #
    # In-app this state is currently unreachable (a real FK on
    # users.reimbursements_person_id plus `has_one :user, dependent: :nullify` on
    # Person), so the branch defends against DB-level damage: a restore or a
    # maintenance script run with FOREIGN_KEY_CHECKS off. Reproduce it the same
    # way, with referential integrity disabled for the delete only.
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

    test "database backend falls back to the email match when the stored FK is dangling" do
      user = users(:user)
      orphan_the_stored_link!(user)
      current = Reimbursements::Person.create!(name: "Current", email: user.email)

      link = PersonLink.new(store: DatabaseStore.new)

      assert_equal current.id, link.person_for(user).id, "the dangling FK must not win"
      assert_equal current.id, user.reload.reimbursements_person_id, "the stale FK is rewritten"
    end

    test "database backend ensure_person! creates no duplicate payee behind a dangling FK" do
      user = users(:user)
      orphan_the_stored_link!(user)
      existing = Reimbursements::Person.create!(name: "Existing", email: user.email)

      link = PersonLink.new(store: DatabaseStore.new)

      assert_no_difference -> { Reimbursements::Person.count } do
        assert_equal existing.id, link.ensure_person!(user).id
      end
      assert_equal existing.id, user.reload.reimbursements_person_id
    end

    # Store-independent proof of the same branch, through the injected-store seam
    # PersonLink is designed around: given a store that reports a stored link
    # whose payee no longer resolves, person_for consults the email match.
    test "a stored link that does not resolve falls through to the email match" do
      user = users(:user)
      match = Reimbursements::Person.new(name: "Match", email: user.email)
      store = StaleLinkStore.new(stored: "404", match: match)

      link = PersonLink.new(store: store)

      assert_same match, link.person_for(user)
      assert_equal [ [ user, match ] ], store.remembered, "the stale link is rewritten"
      assert_equal 0, store.created, "no duplicate payee is created"
    end

    # Minimal store double: reports a stored link that find_person can't resolve.
    class StaleLinkStore
      attr_reader :remembered, :created

      def initialize(stored:, match:)
        @stored = stored
        @match = match
        @remembered = []
        @created = 0
      end

      def stored_person_link(_user) = @stored
      def find_person(_record_id) = nil
      def person_by_email(_email) = @match
      def remember_person_link!(user, person) = @remembered << [ user, person ]

      def create_person!(name:, email:)
        @created += 1
        Reimbursements::Person.new(name: name, email: email)
      end
    end
  end
end
