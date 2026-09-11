module Reimbursements
  ##
  # Pure helpers for the Review page. Nothing here touches the database.
  module ReviewSupport
    BACS_SAFE_PATTERN = /[^a-zA-Z0-9 \-]/
    BACS_MAX_LEN = 18
    DUPLICATE_WINDOW_DAYS = 30

    # Statuses where a needs-attention flag is still actionable: the expense
    # can yet be approved or paid, so an unfixed issue matters. Once Submitted
    # (in EUSA's hands), Paid (done), or Rejected (dead), the same flag is just
    # noise on a non-actionable row — it trains the eye to skip a badge that
    # matters on the rows that are still live.
    ATTENTION_STATUSES = [ Status::DRAFT, Status::PENDING, Status::APPROVED ].freeze

    module_function

    # Whether a needs-attention flag should be surfaced for this expense at all
    # (see ATTENTION_STATUSES).
    def attention_actionable?(expense)
      ATTENTION_STATUSES.include?(expense.status)
    end

    # A BACS-safe payment reference from a budget's display name: drop anything
    # that isn't alphanumeric/space/hyphen, collapse the runs of spaces that
    # leaves, cap at 18 chars, then trim. It is fed Budget#display_name, whose
    # em dash drops out as a space — so "Cogito — Marketing" reads
    # "Cogito Marketing", which is what EUSA saw before the prefix strip.
    def auto_payment_reference(budget_name)
      budget_name.to_s.gsub(BACS_SAFE_PATTERN, "").squeeze(" ")[0, BACS_MAX_LEN].to_s.strip
    end

    # True if an expense has issues to resolve before approving. Thin wrapper over
    # +needs_attention_reasons+ so the flag and its explanation never drift apart.
    def needs_attention(expense, budget_by_id, modulus_checker)
      needs_attention_reasons(expense, budget_by_id, modulus_checker).any?
    end

    # The needs-attention reasons split into the two categories that matter to
    # an operator deciding whether to click Approve:
    #
    #   :blocking — ReviewController#approve_expense REFUSES the approval
    #     (no effective bank details, no linked budget, no non-zero ex-VAT
    #     amount). These MUST be fixed first; this is the single source of
    #     truth kept in lockstep with approve_expense's own guards.
    #   :advisory — approval proceeds, but the operator should look first
    #     (missing/zero gross amount, no receipt, an INVALID modulus result,
    #     or over the budget's remaining). OUTSIDE_SPEC is acceptable; the
    #     modulus check is skipped entirely when there are no bank details.
    #
    # +budget_by_id+ maps record_id => Budget (for the over-budget check);
    # +modulus_checker+ responds to #check(sort, account).
    def attention_summary(expense, budget_by_id, modulus_checker)
      blocking = []
      advisory = []

      amount_reasons(expense, blocking, advisory)
      # Not asked of an international claim: its ex-VAT amount mirrors its
      # gross (no reclaimable UK VAT), so a blank one is already reported as
      # "no GBP amount" and repeating it sends finance looking for a field this
      # rail does not have.
      unless expense.international?
        blocking << "no ex-VAT amount" if expense.amount_excl_vat.nil? || expense.amount_excl_vat.zero?
      end
      blocking << "no budget" if expense.budget.nil? || expense.budget.record_id.blank?
      advisory << "no receipt" if expense.receipts.empty? && expense.sharepoint_receipt_urls.blank?

      if !expense.effective_has_bank_details?
        blocking << "no bank details"
      elsif !expense.international?
        # A UK sort-code/account-number algorithm, so it is skipped rather than
        # run and failed on a payee who has neither.
        modulus = modulus_checker.check(expense.effective_sort_code, expense.effective_account_number)
        advisory << "failed the bank modulus check" if modulus == ModulusCheck::INVALID
      end

      advisory << "over budget" if over_budget?(expense, budget_by_id)
      advisory << "ex-VAT amount exceeds the gross" if excl_vat_over_gross?(expense)
      { blocking: blocking, advisory: advisory }
    end

    # The amount rules, which differ by rail.
    #
    # A UK claim's gross amount is the submitter's own figure and has always
    # been advisory. An international claim needs BOTH figures and cannot be
    # approved without them: +foreign_amount+ is what goes on EUSA's form (their
    # bank pays the supplier in their own currency, so the GBP figure cannot
    # stand in for it), and +amount+ is the GBP equivalent finance types at
    # review — every budget rollup is GBP, so approving without one would book
    # the claim against its budget at nothing.
    def amount_reasons(expense, blocking, advisory)
      unless expense.international?
        advisory << "no amount" if blank_amount?(expense.amount)
        return
      end

      blocking << "no EUR amount" if missing_foreign_amount?(expense)
      blocking << "no GBP amount" if missing_gbp_amount?(expense)
    end
    private_class_method :amount_reasons

    # The two international amount rules, public because
    # ReviewController#approve_blocker refuses on exactly these — the blocking
    # list and the approval guard are documented as being in lockstep, so they
    # read one definition rather than each spelling the rule out.
    def missing_foreign_amount?(expense)
      expense.international? && blank_amount?(expense.foreign_amount)
    end

    def missing_gbp_amount?(expense)
      expense.international? && blank_amount?(expense.amount)
    end

    def blank_amount?(value)
      value.nil? || value.zero?
    end

    # The flat reason list (blocking first, then advisory) — for the CSV export,
    # the attention flag, and anywhere the blocked/advisory split isn't shown.
    def needs_attention_reasons(expense, budget_by_id, modulus_checker)
      summary = attention_summary(expense, budget_by_id, modulus_checker)
      summary[:blocking] + summary[:advisory]
    end

    # Would this expense's ex-VAT amount exceed the loaded budget's remaining?
    # Guards each optional value so it composes with the other (independent)
    # checks in +needs_attention_reasons+ without blowing up on a nil.
    def over_budget?(expense, budget_by_id)
      return false if expense.amount_excl_vat.nil? || expense.budget&.record_id.blank?

      budget = budget_by_id[expense.budget.record_id]
      !budget.nil? && !budget.remaining.nil? && expense.amount_excl_vat > budget.remaining
    end
    private_class_method :over_budget?

    # The ex-VAT amount can never legitimately exceed the gross (VAT is
    # non-negative), yet a real imported claim does exactly this and single-
    # handedly flips its budget over-budget. Flag it (advisory) so the operator
    # catches the data-entry error before it distorts the numbers. Both amounts
    # must be present and non-zero — a 0 sentinel means "not yet known".
    def excl_vat_over_gross?(expense)
      excl = expense.amount_excl_vat
      gross = expense.amount
      return false if excl.nil? || excl.zero? || gross.nil? || gross.zero?

      excl > gross
    end
    private_class_method :excl_vat_over_gross?

    # Map each expense's record_id to other expenses that look like duplicates:
    # same linked person, same gross amount, submitted within +window_days+.
    # Only expenses with a match appear; a blank/absent person is never matched.
    # A missing timestamp counts as within-window (over-warn rather than miss one).
    def find_duplicate_submissions(expenses, window_days: DUPLICATE_WINDOW_DAYS)
      duplicates = {}
      expenses.each_with_index do |first, index|
        expenses[(index + 1)..].each do |second|
          next if first.person.nil? || second.person.nil?
          next if first.person.record_id.blank? || second.person.record_id.blank?
          next if first.person.record_id != second.person.record_id
          next if first.amount != second.amount
          next unless submitted_within?(first.submitted_at, second.submitted_at, window_days)

          (duplicates[first.record_id] ||= []) << second
          (duplicates[second.record_id] ||= []) << first
        end
      end
      duplicates
    end

    # Whole-day gap (floored) within the window.
    def submitted_within?(first_time, second_time, window_days)
      return true if first_time.nil? || second_time.nil?

      (first_time.to_i - second_time.to_i).abs / 86_400 <= window_days
    end
    private_class_method :submitted_within?
  end
end
