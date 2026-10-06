module Reimbursements
  ##
  # Pure helpers for the Review page. Nothing here touches the database.
  module ReviewSupport
    BACS_SAFE_PATTERN = /[^a-zA-Z0-9 \-]/
    BACS_MAX_LEN = 18
    DUPLICATE_WINDOW_DAYS = 30

    # Statuses where a needs-attention flag is still actionable. A flag on a
    # Submitted, Paid or Rejected row trains the eye to skip the badge.
    ATTENTION_STATUSES = [ Status::DRAFT, Status::PENDING, Status::APPROVED ].freeze

    module_function

    def attention_actionable?(expense)
      ATTENTION_STATUSES.include?(expense.status)
    end

    # The modulus result, or nil where the check does not apply: an
    # international claim (IBAN), or no bank details. On a blank pair the
    # checker returns INVALID, so the check is skipped rather than failed.
    def modulus_result(expense, modulus_checker)
      return nil if expense.international? || !expense.effective_has_bank_details?

      modulus_checker.check(expense.effective_sort_code, expense.effective_account_number)
    end

    # The Review queue's tabs; +unmet_ids+ is OwnerReview.unmet_gate_expense_ids
    # over the pending claims. The post-action anchor reads it too, so both agree.
    def split_queue(expenses, unmet_ids)
      pending = expenses.select(&:pending?)
      awaiting_owner, to_approve = pending.partition { |e| unmet_ids.include?(e.record_id) }
      { pending: pending,
        approved: expenses.select { |e| e.status == Status::APPROVED },
        awaiting_owner: awaiting_owner,
        to_approve: to_approve }
    end

    # The To-approve tab's two halves: clean claims, then those with a data
    # problem or a possible duplicate.
    def partition_ready(to_approve, budget_by_id, modulus_checker, duplicates)
      to_approve.partition do |expense|
        !needs_attention(expense, budget_by_id, modulus_checker) &&
          !duplicates.key?(expense.record_id)
      end
    end

    # A BACS-safe reference from Budget#display_name: keep alphanumerics, spaces
    # and hyphens, squeeze spaces, cap at 18 chars, strip
    # ("Cogito: Marketing" -> "Cogito Marketing").
    def auto_payment_reference(budget_name)
      budget_name.to_s.gsub(BACS_SAFE_PATTERN, "").squeeze(" ")[0, BACS_MAX_LEN].to_s.strip
    end

    def needs_attention(expense, budget_by_id, modulus_checker)
      needs_attention_reasons(expense, budget_by_id, modulus_checker).any?
    end

    # :blocking mirrors ReviewController#approve_blocker (approval is refused);
    # :advisory lets approval proceed. OUTSIDE_SPEC is an acceptable modulus result.
    def attention_summary(expense, budget_by_id, modulus_checker)
      blocking = []
      advisory = []

      amount_reasons(expense, blocking, advisory)
      # Not asked of an international claim: ex-VAT mirrors the gross there, so
      # a blank one is already "no GBP amount".
      unless expense.international?
        blocking << "no ex-VAT amount" if expense.amount_excl_vat.nil? || expense.amount_excl_vat.zero?
      end
      blocking << "no budget" if expense.budget.nil?
      advisory << "no receipt" if expense.receipts.empty? && expense.sharepoint_receipt_urls.blank?

      blocking << "no bank details" unless expense.effective_has_bank_details?
      if modulus_result(expense, modulus_checker) == ModulusCheck::INVALID
        advisory << "failed the bank modulus check"
      end

      advisory << "over budget" if over_budget?(expense, budget_by_id)
      advisory << "ex-VAT amount exceeds the gross" if excl_vat_over_gross?(expense)
      { blocking: blocking, advisory: advisory }
    end

    # A UK claim's gross is advisory. An international claim needs both figures:
    # the foreign amount goes on EUSA's form, and every budget rollup counts GBP.
    def amount_reasons(expense, blocking, advisory)
      unless expense.international?
        advisory << "no amount" if blank_amount?(expense.amount)
        return
      end

      blocking << "no #{expense.foreign_currency.presence || 'foreign'} amount" if missing_foreign_amount?(expense)
      blocking << "no GBP amount" if missing_gbp_amount?(expense)
    end
    private_class_method :amount_reasons

    # Public because ReviewController#approve_blocker refuses on exactly these.
    def missing_foreign_amount?(expense)
      expense.international? && blank_amount?(expense.foreign_amount)
    end

    def missing_gbp_amount?(expense)
      expense.international? && blank_amount?(expense.amount)
    end

    def blank_amount?(value)
      value.nil? || value.zero?
    end

    # The flat list, blocking first.
    def needs_attention_reasons(expense, budget_by_id, modulus_checker)
      summary = attention_summary(expense, budget_by_id, modulus_checker)
      summary[:blocking] + summary[:advisory]
    end

    # Would the ex-VAT amount exceed the budget's remaining?
    def over_budget?(expense, budget_by_id)
      return false if expense.amount_excl_vat.nil? || expense.budget.nil?

      budget = budget_by_id[expense.budget.record_id]
      !budget.nil? && !budget.remaining.nil? && expense.amount_excl_vat > budget.remaining
    end
    private_class_method :over_budget?

    # Ex-VAT can never legitimately exceed the gross, yet a real imported claim
    # did and flipped its budget over. A 0 sentinel means "not yet known".
    def excl_vat_over_gross?(expense)
      excl = expense.amount_excl_vat
      gross = expense.amount
      return false if excl.nil? || excl.zero? || gross.nil? || gross.zero?

      excl > gross
    end
    private_class_method :excl_vat_over_gross?

    # record_id => possible duplicates: same linked person, same gross amount,
    # submitted within DUPLICATE_WINDOW_DAYS. A missing timestamp counts as
    # within (over-warn rather than miss one).
    def find_duplicate_submissions(expenses)
      duplicates = {}
      expenses.select(&:person).group_by { |e| [ e.person.record_id, e.amount ] }.each_value do |group|
        group.combination(2) do |first, second|
          next unless submitted_within?(first.submitted_at, second.submitted_at)

          (duplicates[first.record_id] ||= []) << second
          (duplicates[second.record_id] ||= []) << first
        end
      end
      duplicates
    end

    # Whole-day gap (floored) within the window.
    def submitted_within?(first_time, second_time)
      return true if first_time.nil? || second_time.nil?

      (first_time.to_i - second_time.to_i).abs / 86_400 <= DUPLICATE_WINDOW_DAYS
    end
    private_class_method :submitted_within?
  end
end
