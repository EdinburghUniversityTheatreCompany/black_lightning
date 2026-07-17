require "test_helper"

module Reimbursements
  # Ported from bedlam-bacs tests/test_people_helpers.py. Flags People records
  # that share a name or email (case-insensitive) with another record.
  class PeopleSupportTest < ActiveSupport::TestCase
    def person(record_id, name, email)
      Person.new(record_id: record_id, name: name, email: email)
    end

    def ids(people)
      people.map(&:record_id)
    end

    # --- no duplicates -----------------------------------------------------

    test "empty list returns empty" do
      assert_empty PeopleSupport.find_duplicate_people([])
    end

    test "single person is not a duplicate" do
      assert_empty PeopleSupport.find_duplicate_people([ person("rec1", "Alice", "alice@example.com") ])
    end

    test "unique names and emails yield no duplicates" do
      people = [
        person("rec1", "Alice", "alice@example.com"),
        person("rec2", "Bob", "bob@example.com"),
        person("rec3", "Carol", "carol@example.com")
      ]
      assert_empty PeopleSupport.find_duplicate_people(people)
    end

    # --- name duplicates ---------------------------------------------------

    test "duplicate name returns both" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "Alice", "alice@example.com"),
        person("rec2", "Alice", "other@example.com")
      ])
      assert_equal %w[rec1 rec2], ids(result).sort
    end

    test "duplicate name is case-insensitive" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "alice", "alice@example.com"),
        person("rec2", "ALICE", "other@example.com")
      ])
      assert_equal %w[rec1 rec2], ids(result).sort
    end

    test "duplicate name ignores surrounding whitespace" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "  Alice  ", "alice@example.com"),
        person("rec2", "Alice", "other@example.com")
      ])
      assert_equal %w[rec1 rec2], ids(result).sort
    end

    test "three people with the same name all returned" do
      people = [
        person("rec1", "Alice", "a1@example.com"),
        person("rec2", "Alice", "a2@example.com"),
        person("rec3", "Alice", "a3@example.com")
      ]
      assert_equal 3, PeopleSupport.find_duplicate_people(people).length
    end

    # --- email duplicates --------------------------------------------------

    test "duplicate email returns both" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "Alice", "shared@example.com"),
        person("rec2", "Bob", "shared@example.com")
      ])
      assert_equal %w[rec1 rec2], ids(result).sort
    end

    test "duplicate email is case-insensitive" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "Alice", "Shared@EXAMPLE.COM"),
        person("rec2", "Bob", "shared@example.com")
      ])
      assert_equal %w[rec1 rec2], ids(result).sort
    end

    # --- empty fields are never flagged ------------------------------------

    test "empty names are not flagged" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "", "alice@example.com"),
        person("rec2", "", "bob@example.com")
      ])
      assert_empty result
    end

    test "empty emails are not flagged" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "Alice", ""),
        person("rec2", "Bob", "")
      ])
      assert_empty result
    end

    # --- mixed scenarios ---------------------------------------------------

    test "only the name-duplicate is flagged, not the unique one" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "Alice", "alice@example.com"),
        person("rec2", "Alice", "alice2@example.com"),
        person("rec3", "Carol", "carol@example.com")
      ])
      assert_equal %w[rec1 rec2], ids(result).sort
      refute_includes ids(result), "rec3"
    end

    test "order is preserved" do
      people = [
        person("rec1", "Alice", "shared@example.com"),
        person("rec2", "Bob", "bob@example.com"),
        person("rec3", "Carol", "shared@example.com")
      ]
      assert_equal %w[rec1 rec3], ids(PeopleSupport.find_duplicate_people(people))
    end

    test "a person matching on both name and email appears only once" do
      result = PeopleSupport.find_duplicate_people([
        person("rec1", "Alice", "shared@example.com"),
        person("rec2", "Alice", "shared@example.com")
      ])
      assert_equal ids(result).uniq, ids(result)
    end
  end
end
