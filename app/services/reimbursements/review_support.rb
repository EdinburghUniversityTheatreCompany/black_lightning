module Reimbursements
  ##
  # Pure helpers for the Review page. Ported from bedlam-bacs `review_helpers.py`
  # (minus send_rejection_notification, which orchestrates Graph/mailer and lands
  # with the Review UI). All operate on POROs so they unit-test without Airtable.
  module ReviewSupport
    BACS_SAFE_PATTERN = /[^a-zA-Z0-9 \-]/
    BACS_MAX_LEN = 18
    DUPLICATE_WINDOW_DAYS = 30

    module_function

    # A BACS-safe payment reference from a budget name: drop anything that isn't
    # alphanumeric/space/hyphen, cap at 18 chars, then trim.
    def auto_payment_reference(budget_name)
      budget_name.to_s.gsub(BACS_SAFE_PATTERN, "")[0, BACS_MAX_LEN].to_s.strip
    end

    # True if an expense has issues to resolve before approving: missing/zero
    # ex-VAT amount, no linked budget, no receipts, no effective bank details, an
    # INVALID modulus result (OUTSIDE_SPEC is acceptable), or would exceed its
    # budget's remaining. +budget_by_id+ maps record_id => Budget (for the
    # over-budget check); +modulus_checker+ responds to #check(sort, account).
    def needs_attention(expense, budget_by_id, modulus_checker)
      return true if expense.amount_excl_vat.nil? || expense.amount_excl_vat.zero?
      return true if expense.budget.nil? || expense.budget.record_id.blank?
      return true if expense.receipts.empty?
      return true unless expense.effective_has_bank_details?

      modulus = modulus_checker.check(expense.effective_sort_code, expense.effective_account_number)
      return true if modulus == ModulusCheck::INVALID

      budget = budget_by_id[expense.budget.record_id]
      !budget.nil? && !budget.remaining.nil? && expense.amount_excl_vat > budget.remaining
    end

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
