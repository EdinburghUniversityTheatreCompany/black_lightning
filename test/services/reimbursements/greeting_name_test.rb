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

    # An email-shaped name is what PersonLink writes for a linked user with no full name.
    {
      "Pat Producer" => "Pat",
      "Cher" => "Cher",
      "  Pat   Producer  " => "Pat",
      "" => "there",
      "   " => "there",
      "alice@example.com" => "there",
      "alice@example.com Producer" => "there",
      "PAT PRODUCER" => "PAT",
      "van der Berg" => "van"
    }.each do |name, expected|
      test "#{name.inspect} greets as #{expected}" do
        assert_equal expected, GreetingName.for(Person.new(name: name))
      end
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
