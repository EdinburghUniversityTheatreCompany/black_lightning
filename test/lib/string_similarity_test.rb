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

  test "levenshtein_similarity is one minus the distance over the longer length" do
    assert_in_delta 0.8, StringSimilarity.levenshtein_similarity("hello", "hallo")
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
  test "fuzzy_name_match accepts case, punctuation, abbreviation and typo variants" do
    [ %w[John John], %w[JOHN john], %w[Leo Leonardo], %w[Leonardo Leo], %w[John Jon],
      %w[Smith-Jones SmithJones], %w[O'Connor-Smith OConnorSmith], %w[Turnbull Trunbull],
      %w[Johnson Jonson], %w[Anderson Andersen], %w[O'Brien OBrien], %w[D'Angelo DAngelo],
      %w[Michael Micheal], %w[Jean-Pierre JeanPierre] ].each do |a, b|
      assert StringSimilarity.fuzzy_name_match?(a, b), "#{a} / #{b}"
    end
  end

  test "fuzzy_name_match returns false for very different names" do
    [ %w[John Sarah], %w[Michael David], %w[Smith Jones], %w[Turnbull Anderson] ].each do |a, b|
      assert_not StringSimilarity.fuzzy_name_match?(a, b), "#{a} / #{b}"
    end
  end

  test "fuzzy_name_match respects custom threshold" do
    assert_not StringSimilarity.fuzzy_name_match?("John", "Jon", threshold: 0.95)
    assert StringSimilarity.fuzzy_name_match?("John", "Jon", threshold: 0.5)
  end

  test "match_confidence returns 1.0 for exact normalized match" do
    assert_equal 1.0, StringSimilarity.match_confidence("Alex", "Alex")
    assert_equal 1.0, StringSimilarity.match_confidence("Alex", "alex")
    assert_equal 1.0, StringSimilarity.match_confidence("O'Brien", "OBrien")
  end

  test "match_confidence returns 0.9 for abbreviation match" do
    assert_equal 0.9, StringSimilarity.match_confidence("Leo", "Leonardo")
    assert_equal 0.9, StringSimilarity.match_confidence("Alex", "Alexander")
  end

  test "match_confidence returns levenshtein similarity for other matches" do
    confidence = StringSimilarity.match_confidence("John", "Jon")
    assert confidence > 0.6
    assert confidence < 0.9
  end
end
