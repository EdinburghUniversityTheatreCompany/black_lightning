# Name similarity for fuzzy duplicate matching.
module StringSimilarity
  module_function

  # 0.0 (completely different) to 1.0 (identical).
  def levenshtein_similarity(s1, s2)
    return 1.0 if s1 == s2
    return 0.0 if s1.empty? || s2.empty?

    distance = levenshtein_distance(s1, s2)
    1 - (distance.to_f / [ s1.length, s2.length ].max)
  end

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

  # Strips, downcases and removes everything but a-z.
  def normalize_name(name)
    name.to_s.strip.downcase.gsub(/[^a-z]/, "")
  end

  # "Leo" abbreviates "Leonardo".
  def abbreviation?(short, long)
    return false if short.length >= long.length
    long.start_with?(short)
  end

  # 1.0 for an exact normalised match, 0.9 for an abbreviation, otherwise the Levenshtein similarity.
  def match_confidence(name1, name2)
    n1 = normalize_name(name1)
    n2 = normalize_name(name2)

    return 1.0 if n1 == n2
    return 0.9 if abbreviation?(n1, n2) || abbreviation?(n2, n1)

    levenshtein_similarity(n1, n2)
  end

  def fuzzy_name_match?(name1, name2, threshold: 0.6)
    match_confidence(name1, name2) >= threshold
  end
end
