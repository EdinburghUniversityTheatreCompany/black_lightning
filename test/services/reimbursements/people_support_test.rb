require "test_helper"

module Reimbursements
  # Flags People records sharing a name or email with another.
  class PeopleSupportTest < ActiveSupport::TestCase
    def person(name, email) = Person.new(name: name, email: email)

    test "no clash, or only blank names or emails, is not a duplicate" do
      assert_empty PeopleSupport.find_duplicate_people([])
      assert_empty PeopleSupport.find_duplicate_people([ person("Alice", "a@x.com"), person("Bob", "b@x.com") ])
      assert_empty PeopleSupport.find_duplicate_people([ person("", "a@x.com"), person("", "b@x.com") ])
      assert_empty PeopleSupport.find_duplicate_people([ person("Alice", ""), person("Bob", "") ])
    end

    test "a name or email clash ignores case and surrounding space" do
      [ [ "  alice ", "a1@x.com", "ALICE", "a2@x.com" ], [ "Alice", "Shared@X.COM", "Bob", "shared@x.com" ] ].each do |n1, e1, n2, e2|
        a, b, unique = person(n1, e1), person(n2, e2), person("Carol", "c@x.com")

        assert_equal [ a, b ], PeopleSupport.find_duplicate_people([ a, unique, b ])
      end
    end

    test "each duplicate appears once, in input order" do
      a, b = person("Alice", "s@x.com"), person("Alice", "s@x.com")

      assert_equal [ a, b ], PeopleSupport.find_duplicate_people([ a, b ])
    end
  end
end
