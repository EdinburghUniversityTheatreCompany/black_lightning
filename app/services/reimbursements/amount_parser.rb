module Reimbursements
  ##
  # The one lenient parser for typed money: "£1,234.56" and the comma decimal
  # "12,50" (naively stripping the comma would record 100x the amount).
  #
  # #parse answers nil for anything unreadable. #parse! tells blank (nil) from
  # unreadable (raises Error).
  module AmountParser
    class Error < StandardError; end

    module_function

    def parse!(value)
      cleaned = value.to_s.gsub(/[£\s]/, "")
      return nil if cleaned.blank?

      # A trailing "," with 1-2 digits is a decimal comma; any other is thousands.
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
