module Reimbursements
  ##
  # Pure helpers for the Review page. Ported from bedlam-bacs `review_helpers.py`
  # (minus send_rejection_notification, which orchestrates Graph/mailer and lands
  # with the Review UI). All operate on POROs so they unit-test without Airtable.
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

    # A BACS-safe payment reference from a budget name: drop anything that isn't
    # alphanumeric/space/hyphen, cap at 18 chars, then trim.
    def auto_payment_reference(budget_name)
      budget_name.to_s.gsub(BACS_SAFE_PATTERN, "")[0, BACS_MAX_LEN].to_s.strip
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

      advisory << "no amount" if expense.amount.nil? || expense.amount.zero?
      blocking << "no ex-VAT amount" if expense.amount_excl_vat.nil? || expense.amount_excl_vat.zero?
      blocking << "no budget" if expense.budget.nil? || expense.budget.record_id.blank?
      advisory << "no receipt" if expense.receipts.empty? && expense.sharepoint_receipt_urls.blank?

      if expense.effective_has_bank_details?
        modulus = modulus_checker.check(expense.effective_sort_code, expense.effective_account_number)
        advisory << "failed the bank modulus check" if modulus == ModulusCheck::INVALID
      else
        blocking << "no bank details"
      end

      advisory << "over budget" if over_budget?(expense, budget_by_id)
      { blocking: blocking, advisory: advisory }
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

    # Whole-day gap (floor, matching Python timedelta.days) within the window.
    def submitted_within?(first_time, second_time, window_days)
      return true if first_time.nil? || second_time.nil?

      (first_time.to_i - second_time.to_i).abs / 86_400 <= window_days
    end
    private_class_method :submitted_within?
  end
end
