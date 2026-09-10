module Reimbursements
  ##
  # The strict field/column matcher shared by BudgetImport and ExpenseImport.
  #
  # EXACT header names first, then MULTI-WORD phrases only — a bare word is
  # never a substring hint — because "any header containing the keyword" is
  # catastrophic on a sheet whose fields are near-anagrams: read through it, a
  # "Payment reference" column answered to ExpenseImport's dedupe key
  # (collapsing two of a payee's claims into one) and an "Account number"
  # column answered to its expense number (numbering every later claim in the
  # portal from 66,374,959). Neither is catchable downstream, which is why
  # this lives here rather than in ImportParsing#find_column — the membership
  # and user imports keep that looser fallback, whose sheets are flat enough
  # for it.
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
