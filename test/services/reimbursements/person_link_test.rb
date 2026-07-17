require "test_helper"

module Reimbursements
  class PersonLinkTest < ActiveSupport::TestCase
    # Until the DB-backed test migration, these tests exercise the Airtable
    # boundary POROs the Mapper builds.
    Person = Airtable::Person

    # Minimal store fake for link resolution.
    class FakeStore
      attr_reader :created

      def initialize(people)
        @people = people
        @created = []
      end

      def find_person(record_id)
        @people.find { |p| p.record_id == record_id }
      end

      def person_by_email(email)
        @people.find { |p| p.email.casecmp?(email.to_s) }
      end

      def create_person!(name:, email:)
        person = Person.new(record_id: "recCreated", name: name, email: email)
        @created << person
        @people << person
        person
      end
    end

    def pat(record_id: "recPer1")
      Person.new(record_id: record_id, name: "Pat", email: users(:user).email)
    end

    test "uses the stored link when valid" do
      user = users(:user)
      user.update_column(:airtable_person_id, "recPer1") # rubocop:disable Rails/SkipsModelValidations
      link = PersonLink.new(store: FakeStore.new([ pat ]))

      assert_equal "recPer1", link.person_for(user).record_id
    end

    test "falls back to email match and persists the link" do
      user = users(:user)
      assert_nil user.airtable_person_id
      link = PersonLink.new(store: FakeStore.new([ pat ]))

      person = link.person_for(user)

      assert_equal "recPer1", person.record_id
      assert_equal "recPer1", user.reload.airtable_person_id
    end

    test "recovers from a stale stored link via email" do
      user = users(:user)
      user.update_column(:airtable_person_id, "recGone") # rubocop:disable Rails/SkipsModelValidations
      link = PersonLink.new(store: FakeStore.new([ pat ]))

      assert_equal "recPer1", link.person_for(user).record_id
      assert_equal "recPer1", user.reload.airtable_person_id
    end

    test "ensure_person! creates a People record when none matches" do
      user = users(:user)
      store = FakeStore.new([])
      link = PersonLink.new(store: store)

      person = link.ensure_person!(user)

      assert_equal "recCreated", person.record_id
      assert_equal user.email, person.email
      assert_equal "recCreated", user.reload.airtable_person_id
      assert_equal 1, store.created.size
    end

    test "person_for returns nil when unmatched" do
      assert_nil PersonLink.new(store: FakeStore.new([])).person_for(users(:user))
    end
    # --- Database backend: the stored link is the real FK -----------------

    test "database backend resolves and persists the FK link" do
      user = users(:user)
      person = Reimbursements::Person.create!(name: "Pat", email: user.email)
      link = PersonLink.new(store: DatabaseStore.new, backend: "database")

      assert_equal person.id, link.person_for(user).id
      assert_equal person.id, user.reload.reimbursements_person_id
    end

    test "database backend prefers the stored FK over an email match" do
      user = users(:user)
      linked = Reimbursements::Person.create!(name: "Linked", email: "other@example.com")
      Reimbursements::Person.create!(name: "Email Match", email: user.email)
      user.update_column(:reimbursements_person_id, linked.id)

      link = PersonLink.new(store: DatabaseStore.new, backend: "database")
      assert_equal linked.id, link.person_for(user).id
    end

    test "database backend creates the payee on first submission" do
      user = users(:user)
      link = PersonLink.new(store: DatabaseStore.new, backend: "database")

      person = link.ensure_person!(user)
      assert_equal user.email, person.email
      assert_equal person.id, user.reload.reimbursements_person_id
      assert_nil user.airtable_person_id
    end
  end
end
