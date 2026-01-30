# Module providing string similarity functions for fuzzy matching.
module StringSimilarity
  module_function

  # Calculates the Levenshtein similarity between two strings.
  # Returns a value between 0.0 (completely different) and 1.0 (identical).
  def levenshtein_similarity(s1, s2)
    return 1.0 if s1 == s2
    return 0.0 if s1.empty? || s2.empty?

    distance = levenshtein_distance(s1, s2)
    1 - (distance.to_f / [ s1.length, s2.length ].max)
  end

  # Calculates the Levenshtein distance (edit distance) between two strings.
  # Returns the minimum number of single-character edits needed to change one string into the other.
  def levenshtein_distance(s1, s2)
    return s2.length if s1.empty?
    return s1.length if s2.empty?

    matrix = Array.new(s1.length + 1) { |i| [ i ] + [ 0 ] * s2.length }
    matrix[0] = (0..s2.length).to_a

    s1.each_char.with_index do |c1, i|
      s2.each_char.with_index do |c2, j|
        cost = c1 == c2 ? 0 : 1
        matrix[i + 1][j + 1] = [
          matrix[i][j + 1] + 1,     # deletion
          matrix[i + 1][j] + 1,     # insertion
          matrix[i][j] + cost       # substitution
        ].min
      end
    end

    matrix[s1.length][s2.length]
  end

  # Normalizes a name for comparison by stripping, downcasing, and removing non-letters.
  def normalize_name(name)
    name.to_s.strip.downcase.gsub(/[^a-z]/, "")
  end

  # Checks if one name is an abbreviation of another.
  # E.g., "Leo" is an abbreviation of "Leonardo"
  def abbreviation?(short, long)
    return false if short.length >= long.length
    long.start_with?(short)
  end

  # Fuzzy matches two names using normalization, abbreviation check, and Levenshtein similarity.
  # Returns true if the names are considered a match.
  def fuzzy_name_match?(name1, name2, threshold: 0.6)
    n1 = normalize_name(name1)
    n2 = normalize_name(name2)

    return true if n1 == n2
    return true if abbreviation?(n1, n2) || abbreviation?(n2, n1)

    levenshtein_similarity(n1, n2) >= threshold
  end
end
