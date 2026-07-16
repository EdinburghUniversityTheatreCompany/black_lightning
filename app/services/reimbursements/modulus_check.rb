module Reimbursements
  ##
  # UK bank account modulus check — the Pay.UK (formerly VocaLink) algorithm that
  # verifies a sort code + account number are mathematically consistent. This is
  # NOT Confirmation of Payee; it only catches typos (transposed/dropped/miskeyed
  # digits). Ported wholesale from bedlam-bacs `modulus_check.py`.
  #
  # Rule data (`valacdos.txt`, `scsubtab.txt`) comes from Pay.UK under a
  # click-through licence; it is vendored in vendor/pay_uk/ and committed so Kamal
  # ships it inside the image. When the files are absent every check reads
  # OUTSIDE_SPEC — a soft "couldn't verify", never a hard block.
  #
  # Exceptions implemented: 1, 3, 4, 5, 6, 7. 14 is recognised but treated as
  # OUTSIDE_SPEC; any other exception falls back to OUTSIDE_SPEC for safety.
  module ModulusCheck
    VALID = :valid
    INVALID = :invalid
    OUTSIDE_SPEC = :outside_spec

    # Recognised exception codes. 14 is recognised but always OUTSIDE_SPEC (below).
    SUPPORTED_EXCEPTIONS = [ 0, 1, 3, 4, 5, 6, 7, 14 ].freeze

    # Location of the vendored Pay.UK rule files (gitignored; see
    # vendor/pay_uk/README.md).
    VALACDOS_PATH = -> { Rails.root.join("vendor/pay_uk/valacdos.txt") }
    SCSUBTAB_PATH = -> { Rails.root.join("vendor/pay_uk/scsubtab.txt") }

    module_function

    # A process-wide checker built from the vendored rule files, loaded once.
    # Missing files yield an empty rule set, so every check reads OUTSIDE_SPEC
    # rather than raising (never a hard block on a receipt review).
    def default_checker
      @default_checker ||= Checker.from_files(VALACDOS_PATH.call, SCSUBTAB_PATH.call)
    end

    # Drops the memoized checker so the next call reloads the rule files. Test
    # seam; not used in production.
    def reset_default_checker!
      @default_checker = nil
    end

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
      # 9 digits is the Pay.UK "nonstandard" Santander/A&L format, handled by
      # #normalize_pair. Returns VALID / INVALID / OUTSIDE_SPEC.
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
        # Exception 14 (building-society roll-number accounts) checks a digit subset;
        # conservatively treat as outside spec rather than risk a false negative.
        return OUTSIDE_SPEC if applicable.any? { |rule| rule.exception == 14 }

        results = applicable.map { |rule| apply_rule(rule, sort_clean, account_clean) }

        # A sorting code with two weighting rows must pass BOTH checks, unless an
        # exception says otherwise. Pay.UK spec §2.2.2.5 does NOT relax this for
        # exception 5 (unlike exceptions 10/11 and 12/13, which are "either check"):
        # both the MOD11 and DBLAL checks must pass, each via the exception-5
        # checkdigit comparison in #apply_rule. (Spec test case 23: first check
        # passes, second fails -> INVALID.)
        results.all? ? VALID : INVALID
      end

      # Only dashes/spaces are documented separators — anything else (a stray
      # letter, a typo) must fail normalization rather than being silently
      # discarded, or a corrupted value could coincidentally reduce to a
      # clean, valid-looking digit string and read VALID.
      def self.normalize_sort_code(sort_code)
        cleaned = strip_separators(sort_code)
        cleaned && cleaned.length == 6 ? cleaned : ""
      end

      # Valid lengths per Pay.UK: 6, 7, 8 (left-padded to 8) or 10 (last 8
      # kept). A 9-digit input is handled by #normalize_pair instead, since it
      # also changes the sort code and can't be normalized in isolation.
      def self.normalize_account_number(account_number)
        cleaned = strip_separators(account_number)
        return "" unless cleaned && [ 6, 7, 8, 10 ].include?(cleaned.length)

        cleaned = cleaned[2..] if cleaned.length == 10
        cleaned.rjust(8, "0")
      end

      # Normalizes a sort code + account number TOGETHER — needed because a
      # 9-digit account number (Pay.UK spec §2.1.2 "Nonstandard account
      # numbers", e.g. Santander / Alliance & Leicester Commercial Bank)
      # substitutes the sort code's last digit with the account number's own
      # first digit before only the last 8 digits are checked, rather than
      # being hard-rejected as INVALID. Returns ["", ""] when either side
      # can't be normalized at all.
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
        cleaned = value.to_s.gsub(/[\-\s]/, "")
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
          # Foreign-currency accounts (Pay.UK spec §2.2.2.6): pass if account[0]
          # is 4-8 and account digits g (account[6]) and h (account[7]) match —
          # not account[0] and account[6], a different digit pair entirely.
          return true if (4..8).cover?(account_digits[0]) && account_digits[6] == account_digits[7]
        when 7
          # If account digit g (account[6]) is 9, zero weighting positions u-b
          # (Pay.UK spec §2.2.2.7): all 6 sort-code weights plus the first 2
          # account-number weights (positions 0-7 of 14), not just the 6
          # sort-code weights.
          weights = [ 0, 0, 0, 0, 0, 0, 0, 0, *weights[8..] ] if account_digits[6] == 9
        when 3
          # If account digit c (account[2]) is 6 or 9, the rule doesn't apply (passes).
          return true if [ 6, 9 ].include?(account_digits[2])
        end
        # Exceptions 1 and 4 are handled in the totalling step / after it below;
        # exception 5 has its own checkdigit comparison, also below.

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

        # Exception 5 (Pay.UK spec §2.2.2.5): the checkdigit is compared against
        # (modulus - remainder), not a plain zero remainder. The first (MOD11)
        # check uses digit g = account[6]; the second (DBLAL) check uses digit
        # h = account[7]. The weighting zeroes out the checkdigit position so it
        # does not contribute to the sum.
        return exception5_pass?(rule.algorithm, remainder, account_digits) if rule.exception == 5

        # Exception 4: pass if the remainder equals the last two account digits.
        return remainder == account_number[6, 2].to_i if rule.exception == 4

        remainder.zero?
      end

      # Checkdigit comparison for exception 5. MOD11 (first check): remainder 0
      # passes only when g is 0; remainder 1 always fails; otherwise valid when
      # 11 - remainder == g. DBLAL (second check): remainder 0 passes only when h
      # is 0; otherwise valid when 10 - remainder == h.
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
