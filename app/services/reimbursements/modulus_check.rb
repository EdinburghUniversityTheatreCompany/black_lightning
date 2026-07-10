module Reimbursements
  ##
  # UK bank account modulus check — the Pay.UK (formerly VocaLink) algorithm that
  # verifies a sort code + account number are mathematically consistent. This is
  # NOT Confirmation of Payee; it only catches typos (transposed/dropped/miskeyed
  # digits). Ported wholesale from bedlam-bacs `modulus_check.py`.
  #
  # Rule data (`valacdos.txt`, `scsubtab.txt`) comes from Pay.UK under a
  # click-through licence, so it is vendored (gitignored), not committed. When the
  # files are absent every check reads OUTSIDE_SPEC — a soft "couldn't verify",
  # never a hard block.
  #
  # Exceptions implemented: 1, 3, 4, 5, 6, 7. 14 is recognised but treated as
  # OUTSIDE_SPEC; any other exception falls back to OUTSIDE_SPEC for safety.
  module ModulusCheck
    VALID = :valid
    INVALID = :invalid
    OUTSIDE_SPEC = :outside_spec

    # Recognised exception codes. 14 is recognised but always OUTSIDE_SPEC (below).
    SUPPORTED_EXCEPTIONS = [ 0, 1, 3, 4, 5, 6, 7, 14 ].freeze

    ##
    # One line from valacdos.txt: a sort-code range, a method, 14 weights
    # (6 for the sort code + 8 for the account number) and an exception code.
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

      # Validate a sort code + account number. Sort code: 6 digits, dashes/spaces
      # allowed. Account number: 6/7/8 digits (padded to 8) or 10 (last 8 kept);
      # 9-digit inputs are rejected. Returns VALID / INVALID / OUTSIDE_SPEC.
      def check(sort_code, account_number)
        sort_clean = self.class.normalize_sort_code(sort_code)
        account_clean = self.class.normalize_account_number(account_number)
        return INVALID if sort_clean.empty? || account_clean.empty?

        sort_int = sort_clean.to_i
        if @substitutions.key?(sort_int)
          sort_int = @substitutions[sort_int]
          sort_clean = format("%06d", sort_int)
        end

        applicable = @rules.select { |rule| rule.applies_to?(sort_int) }
        return OUTSIDE_SPEC if applicable.empty?
        return OUTSIDE_SPEC if applicable.any? { |rule| !SUPPORTED_EXCEPTIONS.include?(rule.exception) }
        # Exception 14 (building-society roll-number accounts) checks a digit subset;
        # conservatively treat as outside spec rather than risk a false negative.
        return OUTSIDE_SPEC if applicable.any? { |rule| rule.exception == 14 }

        results = applicable.map { |rule| apply_rule(rule, sort_clean, account_clean) }

        # Exception 5 with two rules: VALID if EITHER passes (OR, not AND).
        if applicable.length == 2 && applicable.any? { |rule| rule.exception == 5 }
          return results.any? ? VALID : INVALID
        end

        results.all? ? VALID : INVALID
      end

      def self.normalize_sort_code(sort_code)
        cleaned = sort_code.to_s.gsub(/\D/, "")
        cleaned.length == 6 ? cleaned : ""
      end

      # Valid lengths per Pay.UK: 6, 7, 8 (left-padded to 8) or 10 (last 8 kept).
      def self.normalize_account_number(account_number)
        cleaned = account_number.to_s.gsub(/\D/, "")
        return "" unless [ 6, 7, 8, 10 ].include?(cleaned.length)

        cleaned = cleaned[2..] if cleaned.length == 10
        cleaned.rjust(8, "0")
      end

      private

      def apply_rule(rule, sort_code, account_number)
        digits = (sort_code + account_number).chars.map(&:to_i) # 14 digits
        weights = rule.weights.dup
        account_digits = account_number.chars.map(&:to_i)

        case rule.exception
        when 6
          # Foreign-currency accounts: pass if account[0] in 4..8 and account[0]==account[6].
          return true if (4..8).cover?(account_digits[0]) && account_digits[0] == account_digits[6]
        when 7
          # If account digit g (account[6]) is 9, zero the sort-code weights (positions 0-5).
          weights = [ 0, 0, 0, 0, 0, 0, *weights[6..] ] if account_digits[6] == 9
        when 3
          # If account digit c (account[2]) is 6 or 9, the rule doesn't apply (passes).
          return true if [ 6, 9 ].include?(account_digits[2])
        end
        # Exceptions 1, 4, 5 are handled in the totalling step / in #check.

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

        # Exception 4: pass if the remainder equals the last two account digits.
        return remainder == account_number[6, 2].to_i if rule.exception == 4

        remainder.zero?
      end
    end

    ##
    # Parsers for the whitespace-delimited Pay.UK data files. Missing files and
    # malformed lines are skipped, never raised.
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
