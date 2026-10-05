module Reimbursements
  ##
  # The strict header matcher shared by BudgetImport and ExpenseImport: EXACT
  # names first, then MULTI-WORD phrases only. A bare-word substring match read
  # an "Account number" column as ExpenseImport's expense number and numbered
  # every later claim from 66,374,959. ImportParsing#find_column keeps the
  # looser fallback for the flatter membership and user sheets.
  #
  # The includer defines FIELDS: field => { label:, exact: [...], contains: [...] },
  # each entry already normalised (#normalize_header).
  module StrictColumnMatching
    extend ActiveSupport::Concern

    private

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
