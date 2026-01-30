require "test_helper"

class StringSimilarityTest < ActiveSupport::TestCase
  # levenshtein_distance tests
  test "levenshtein_distance returns 0 for identical strings" do
    assert_equal 0, StringSimilarity.levenshtein_distance("hello", "hello")
  end

  test "levenshtein_distance returns correct distance for single character difference" do
    assert_equal 1, StringSimilarity.levenshtein_distance("hello", "hallo")
  end

  test "levenshtein_distance returns string length for empty comparison" do
    assert_equal 5, StringSimilarity.levenshtein_distance("hello", "")
    assert_equal 5, StringSimilarity.levenshtein_distance("", "hello")
  end

  test "levenshtein_distance handles insertions deletions and substitutions" do
    assert_equal 3, StringSimilarity.levenshtein_distance("kitten", "sitting")
  end

  # levenshtein_similarity tests
  test "levenshtein_similarity returns 1.0 for identical strings" do
    assert_equal 1.0, StringSimilarity.levenshtein_similarity("hello", "hello")
  end

  test "levenshtein_similarity returns 0.0 for empty string comparison" do
    assert_equal 0.0, StringSimilarity.levenshtein_similarity("hello", "")
    assert_equal 0.0, StringSimilarity.levenshtein_similarity("", "hello")
  end

  test "levenshtein_similarity returns value between 0 and 1" do
    similarity = StringSimilarity.levenshtein_similarity("hello", "hallo")
    assert similarity > 0.0 && similarity < 1.0
  end

  # normalize_name tests
  test "normalize_name strips and downcases" do
    assert_equal "hello", StringSimilarity.normalize_name("  HELLO  ")
  end

  test "normalize_name removes non-letter characters" do
    assert_equal "obrien", StringSimilarity.normalize_name("O'Brien")
    assert_equal "jeanpierre", StringSimilarity.normalize_name("Jean-Pierre")
  end

  # abbreviation? tests
  test "abbreviation returns true when first is prefix of second" do
    assert StringSimilarity.abbreviation?("leo", "leonardo")
  end

  test "abbreviation returns false when lengths are equal" do
    assert_not StringSimilarity.abbreviation?("john", "john")
  end

  test "abbreviation returns false when first is not prefix" do
    assert_not StringSimilarity.abbreviation?("leo", "jonathan")
  end

  # fuzzy_name_match? tests
  test "fuzzy_name_match returns true for exact match" do
    assert StringSimilarity.fuzzy_name_match?("John", "John")
  end

  test "fuzzy_name_match returns true for case insensitive match" do
    assert StringSimilarity.fuzzy_name_match?("JOHN", "john")
  end

  test "fuzzy_name_match returns true for abbreviations" do
    assert StringSimilarity.fuzzy_name_match?("Leo", "Leonardo")
    assert StringSimilarity.fuzzy_name_match?("Leonardo", "Leo")
  end

  test "fuzzy_name_match returns true for similar names" do
    assert StringSimilarity.fuzzy_name_match?("John", "Jon")
  end

  test "fuzzy_name_match returns false for very different names" do
    assert_not StringSimilarity.fuzzy_name_match?("John", "Sarah")
  end

  test "fuzzy_name_match handles special characters" do
    assert StringSimilarity.fuzzy_name_match?("O'Brien", "OBrien")
  end

  test "fuzzy_name_match respects custom threshold" do
    # With high threshold, similar names should not match
    assert_not StringSimilarity.fuzzy_name_match?("John", "Jon", threshold: 0.95)
    # With low threshold, different names might match
    assert StringSimilarity.fuzzy_name_match?("John", "Jon", threshold: 0.5)
  end
end
