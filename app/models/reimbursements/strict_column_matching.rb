module Reimbursements
  ##
  # The strict field/column matcher shared by BudgetImport and ExpenseImport.
  #
  # EXACT header names first, then MULTI-WORD phrases only — a bare word is
  # never a substring hint — because "any header containing the keyword" is
  # catastrophic on a sheet whose fields are near-anagrams: read that way, an
  # "Account number" column answered to ExpenseImport's expense number and
  # numbered every later claim in the portal from 66,374,959. Not catchable
  # downstream, which is why this is separate from ImportParsing#find_column,
  # whose looser fallback the flatter membership and user sheets keep.
  #
  # Including class must define FIELDS: a Hash of
  # field => { label:, exact: [...], contains: [...] }. Each entry is written
  # already normalised (see #normalize_header).
  module StrictColumnMatching
    extend ActiveSupport::Concern

    private

    # Punctuation and case carry no meaning in a spreadsheet heading, so
    # "E-mail", "e mail" and "EMAIL" are one name.
    def normalize_header(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def match_header(headers, spec)
      spec[:exact].each do |name|
        found = headers.find { |header| normalize_header(header) == name }
        return found if found
      end
      spec[:contains].each do |phrase|
        found = headers.find { |header| normalize_header(header).include?(phrase) }
        return found if found
      end
      nil
    end
  end
end
