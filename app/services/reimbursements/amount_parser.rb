module Reimbursements
  ##
  # The one lenient money parser for typed amounts, extracted from ExpenseForm
  # so the finance forms read a number exactly the way the submitter form does.
  # Accepts "£1,234.56" (currency symbol, spaces, thousands separators) and
  # "12,50" (comma decimal — common for international students; naively
  # stripping the comma would record a 100x amount).
  #
  # The budget forms used to hand the raw string straight to BigDecimal(), which
  # raises on both of those formats, and their rescue-to-nil then meant "the
  # operator left this blank" — so a typed "1,200" was silently dropped.
  #
  # #parse answers nil for anything unreadable. #parse! separates the two cases
  # a caller may need to tell apart: nil for "nothing was typed", an exception
  # for "something was typed and it isn't a number".
  module AmountParser
    # Raised by .parse! for a non-blank value that isn't a number.
    class Error < StandardError; end

    module_function

    def parse!(value)
      cleaned = value.to_s.gsub(/[£\s]/, "")
      return nil if cleaned.blank?

      # A trailing "," with 1-2 digits is a decimal comma; anywhere else a comma
      # is a thousands separator.
      cleaned = if cleaned.match?(/,\d{1,2}\z/) && cleaned.exclude?(".")
        cleaned.tr(",", ".")
      else
        cleaned.delete(",")
      end
      BigDecimal(cleaned)
    rescue ArgumentError
      raise Error, "#{value} is not an amount"
    end

    def parse(value)
      parse!(value)
    rescue Error
      nil
    end
  end
end
