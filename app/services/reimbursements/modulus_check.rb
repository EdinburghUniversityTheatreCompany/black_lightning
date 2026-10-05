module Reimbursements
  ##
  # UK bank account modulus check: the Pay.UK algorithm that verifies a sort
  # code and account number are consistent. Not Confirmation of Payee; it only
  # catches typos.
  #
  # The rule files are Pay.UK's, committed in vendor/pay_uk/ so the image ships
  # them. Without them every check reads OUTSIDE_SPEC, a soft "couldn't verify".
  # Exception 14 (building-society roll numbers) reads OUTSIDE_SPEC rather than
  # risk a false negative, as does any exception not supported.
  module ModulusCheck
    VALID = :valid
    INVALID = :invalid
    OUTSIDE_SPEC = :outside_spec

    # 14 is recognised but always OUTSIDE_SPEC (see #check).
    SUPPORTED_EXCEPTIONS = [ 0, 1, 3, 4, 5, 6, 7, 14 ].freeze

    VALACDOS_PATH = -> { Rails.root.join("vendor/pay_uk/valacdos.txt") }
    SCSUBTAB_PATH = -> { Rails.root.join("vendor/pay_uk/scsubtab.txt") }

    module_function

    # Built once from the vendored rule files.
    def default_checker
      @default_checker ||= Checker.from_files(VALACDOS_PATH.call, SCSUBTAB_PATH.call)
    end

    # Test seam; not used in production.
    def reset_default_checker!
      @default_checker = nil
    end

    ##
    # One valacdos.txt line: a sort-code range, a method, 14 weights (6 sort
    # code, 8 account) and an exception code.
    Rule = Data.define(:sort_from, :sort_to, :algorithm, :weights, :exception) do
      def applies_to?(sort_code)
        sort_from <= sort_code && sort_code <= sort_to
      end
    end

    class Checker
      def initialize(rules, substitutions = {})
        @rules = rules
        @substitutions = substitutions
      end

      def self.from_files(valacdos_path, scsubtab_path)
        new(Parser.parse_valacdos(valacdos_path), Parser.parse_scsubtab(scsubtab_path))
      end

      # Returns VALID, INVALID or OUTSIDE_SPEC. Sort code: 6 digits, dashes or
      # spaces allowed. Account: see #normalize_account_number and #normalize_pair.
      def check(sort_code, account_number)
        sort_clean, account_clean = self.class.normalize_pair(sort_code, account_number)
        return INVALID if sort_clean.empty? || account_clean.empty?

        sort_int = sort_clean.to_i
        if @substitutions.key?(sort_int)
          sort_int = @substitutions[sort_int]
          sort_clean = format("%06d", sort_int)
        end

        applicable = @rules.select { |rule| rule.applies_to?(sort_int) }
        return OUTSIDE_SPEC if applicable.empty?
        return OUTSIDE_SPEC if applicable.any? { |rule| !SUPPORTED_EXCEPTIONS.include?(rule.exception) }
        # Exception 14 checks a digit subset: outside spec rather than risk a false negative.
        return OUTSIDE_SPEC if applicable.any? { |rule| rule.exception == 14 }

        results = applicable.map { |rule| apply_rule(rule, sort_clean, account_clean) }

        # Two weighting rows must BOTH pass. Spec §2.2.2.5 does not relax that
        # for exception 5 (unlike 10/11 and 12/13): spec test case 23, first
        # check passing and second failing, is INVALID.
        results.all? ? VALID : INVALID
      end

      # Only dashes and spaces are separators: a stray letter must fail, not be
      # dropped and leave a valid-looking digit string.
      def self.normalize_sort_code(sort_code)
        cleaned = strip_separators(sort_code)
        cleaned && cleaned.length == 6 ? cleaned : ""
      end

      # 6, 7 or 8 digits (left-padded to 8) or 10 (last 8 kept). 9 digits is
      # #normalize_pair's, as it changes the sort code too.
      def self.normalize_account_number(account_number)
        cleaned = strip_separators(account_number)
        return "" unless cleaned && [ 6, 7, 8, 10 ].include?(cleaned.length)

        cleaned = cleaned[2..] if cleaned.length == 10
        cleaned.rjust(8, "0")
      end

      # A 9-digit account (spec §2.1.2, e.g. Santander) replaces the sort
      # code's last digit with its own first digit, then checks its last 8.
      # Returns ["", ""] when either side cannot be normalized.
      def self.normalize_pair(sort_code, account_number)
        sort_clean = normalize_sort_code(sort_code)
        account_digits = strip_separators(account_number)
        return [ "", "" ] if sort_clean.empty? || account_digits.nil?

        if account_digits.length == 9
          [ sort_clean[0, 5] + account_digits[0], account_digits[1..] ]
        else
          [ sort_clean, normalize_account_number(account_number) ]
        end
      end

      def self.strip_separators(value)
        # A literal space, not \s: a tab pasted from a spreadsheet must not
        # reduce to clean digits.
        cleaned = value.to_s.gsub(/[\- ]/, "")
        cleaned.match?(/\A\d+\z/) ? cleaned : nil
      end
      private_class_method :strip_separators

      private

      def apply_rule(rule, sort_code, account_number)
        digits = (sort_code + account_number).chars.map(&:to_i) # 14 digits
        weights = rule.weights.dup
        account_digits = account_number.chars.map(&:to_i)

        case rule.exception
        when 6
          # Spec §2.2.2.6: pass if a (account[0]) is 4-8 and g == h
          # (account[6], account[7]); not a == g.
          return true if (4..8).cover?(account_digits[0]) && account_digits[6] == account_digits[7]
        when 7
          # Spec §2.2.2.7: if g (account[6]) is 9, zero positions u-b, the six
          # sort-code weights AND the first two account weights.
          weights = [ 0, 0, 0, 0, 0, 0, 0, 0, *weights[8..] ] if account_digits[6] == 9
        when 3
          # c (account[2]) of 6 or 9: the rule does not apply.
          return true if [ 6, 9 ].include?(account_digits[2])
        end

        case rule.algorithm
        when "DBLAL"
          total = 0
          digits.zip(weights).each do |digit, weight|
            product = digit * weight
            total += (product / 10) + (product % 10) # double-add-low-add: sum the product's digits
          end
          total += 27 if rule.exception == 1
          remainder = total % 10
        when "MOD10"
          remainder = digits.zip(weights).sum { |digit, weight| digit * weight } % 10
        when "MOD11"
          remainder = digits.zip(weights).sum { |digit, weight| digit * weight } % 11
        else
          return false # unknown method
        end

        # Exception 5 (spec §2.2.2.5) compares a checkdigit with modulus less
        # remainder: g (account[6]) for MOD11, h (account[7]) for DBLAL.
        return exception5_pass?(rule.algorithm, remainder, account_digits) if rule.exception == 5

        # Exception 4: pass if the remainder equals the last two account digits.
        return remainder == account_number[6, 2].to_i if rule.exception == 4

        remainder.zero?
      end

      def exception5_pass?(algorithm, remainder, account_digits)
        case algorithm
        when "MOD11"
          g = account_digits[6]
          return g.zero? if remainder.zero?
          return false if remainder == 1

          (11 - remainder) == g
        when "DBLAL"
          h = account_digits[7]
          return h.zero? if remainder.zero?

          (10 - remainder) == h
        else
          false
        end
      end
    end

    ##
    # Missing files and malformed lines are skipped, never raised. Integer(x, 10)
    # because a leading zero would otherwise read as octal.
    module Parser
      module_function

      def parse_valacdos(path)
        rules = []
        return rules unless File.exist?(path)

        File.foreach(path) do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          parts = line.split
          next if parts.length < 17

          begin
            rules << Rule.new(
              sort_from: Integer(parts[0], 10),
              sort_to: Integer(parts[1], 10),
              algorithm: parts[2],
              weights: parts[3, 14].map { |part| Integer(part, 10) },
              exception: parts.length >= 18 ? Integer(parts[17], 10) : 0
            )
          rescue ArgumentError
            next # skip malformed lines
          end
        end

        rules
      end

      def parse_scsubtab(path)
        subs = {}
        return subs unless File.exist?(path)

        File.foreach(path) do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          parts = line.split
          next if parts.length < 2

          begin
            subs[Integer(parts[0], 10)] = Integer(parts[1], 10)
          rescue ArgumentError
            next
          end
        end

        subs
      end
    end
  end
end
