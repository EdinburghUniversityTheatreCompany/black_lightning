require "test_helper"

module Reimbursements
  class GreetingNameTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # A payee with no #user at all — the reason +for+ goes through #try.
    NamedOnly = Struct.new(:name)

    def link(person, user)
      user.update_column(:reimbursements_person_id, person.id)
      person.reload
    end

    test "prefers the linked account's own first_name over the registry name" do
      user = users(:user)
      person = create_reimbursements_person(name: "Pat Producer", email: user.email)
      link(person, user)

      assert_equal user.first_name, GreetingName.for(person)
      assert_not_equal "Pat", GreetingName.for(person)
    end

    test "falls back to the registry name when the linked account has no first_name" do
      user = users(:user)
      person = create_reimbursements_person(name: "Pat Producer", email: user.email)
      link(person, user)

      user.update_column(:first_name, nil)
      assert_equal "Pat", GreetingName.for(person.reload)

      user.update_column(:first_name, "   ")
      assert_equal "Pat", GreetingName.for(person.reload)
    end

    test "uses the leading word of the registry name when there is no linked account" do
      assert_equal "Pat", GreetingName.for(Person.new(name: "Pat Producer"))
    end

    test "a single-word name is used whole" do
      assert_equal "Cher", GreetingName.for(Person.new(name: "Cher"))
    end

    test "surrounding and repeated whitespace is ignored" do
      assert_equal "Pat", GreetingName.for(Person.new(name: "  Pat   Producer  "))
    end

    test "a blank name greets generically" do
      assert_equal "there", GreetingName.for(Person.new(name: ""))
      assert_equal "there", GreetingName.for(Person.new(name: "   "))
    end

    # PersonLink writes this row shape whenever a linked user has no full name.
    test "an email-address name greets generically" do
      assert_equal "there", GreetingName.for(Person.new(name: "alice@example.com"))
      assert_equal "there", GreetingName.for(Person.new(name: "alice@example.com Producer"))
    end

    test "a hyphenated first name is kept whole" do
      assert_equal "Anne-Marie", GreetingName.for(Person.new(name: "Anne-Marie Dupont"))
    end

    test "non-ASCII names pass through unchanged" do
      assert_equal "Zoë", GreetingName.for(Person.new(name: "Zoë Müller"))
      assert_equal "Seán", GreetingName.for(Person.new(name: "Seán Ó Briain"))
    end

    # Titlecasing would mangle McDonald, O'Brien and van der Berg.
    test "the name's own capitalisation is preserved" do
      assert_equal "PAT", GreetingName.for(Person.new(name: "PAT PRODUCER"))
      assert_equal "van", GreetingName.for(Person.new(name: "van der Berg"))
    end

    # Expense belongs_to :person is optional, so created_html can hand us nil.
    test "a nil payee greets generically" do
      assert_equal "there", GreetingName.for(nil)
    end

    test "a payee-shaped value without a linked account still works" do
      assert_equal "Pat", GreetingName.for(NamedOnly.new("Pat Producer"))
    end
  end
end
