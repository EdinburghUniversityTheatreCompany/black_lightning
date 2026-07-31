module Reimbursements
  ##
  # Form object for submitting/editing an expense. When submitting, it enforces
  # every field finance requires — the portal must not be a way around them.
  # Saving as a DRAFT relaxes the presence rules (like
  # email-in, gaps are completed later); format rules still apply to whatever
  # was filled in, and submitting the draft re-runs the full validation.
  #
  # The VAT rule is a SOFT block: when the ex-VAT amount isn't below the total,
  # submitters must tick an acknowledgement,
  # because the full amount then counts against their budget — but they can
  # always submit.
  class ExpenseForm
    include ActiveModel::Model

    # What a receipt may be STORED as.
    ALLOWED_RECEIPT_TYPES = %w[application/pdf image/jpeg image/png image/webp].freeze
    # Accepted at intake but never stored as-is: iOS photographs default to
    # HEIC, so these are converted to JPEG before anything is attached (see
    # ReceiptIntake).
    CONVERTED_RECEIPT_TYPES = %w[image/heic image/heif].freeze
    ACCEPTED_RECEIPT_TYPES = (ALLOWED_RECEIPT_TYPES + CONVERTED_RECEIPT_TYPES).freeze
    # The file input's accept attribute. The extensions are listed alongside the
    # types because browsers vary in which they match a HEIC file against, and a
    # picker that filters the photo out is indistinguishable from "not allowed".
    RECEIPT_ACCEPT_ATTRIBUTE = (ACCEPTED_RECEIPT_TYPES + %w[.heic .heif]).join(",").freeze
    MAX_RECEIPT_BYTES = 5.megabytes # per-receipt upload cap; a batch mails them all as attachments
    REFERENCE_LIMIT = 18 # EUSA truncates payment references beyond this

    attr_accessor :expense_type, :amount, :amount_excl_vat, :budget_record_id,
                  :description, :payment_reference, :payee_name_override,
                  :sort_code_override, :account_number_override,
                  :vat_acknowledged, :save_as_draft,
                  :large_amount_acknowledged, :expense_receipt_count
    attr_writer :receipts, :require_receipts, :internal

    # Above this, submitting asks for a one-tick confirmation — the realistic
    # error is typing pence as pounds (4999 for 49.99) or a stray digit, which
    # would otherwise sail into the finance queue and skew a budget.
    LARGE_AMOUNT_THRESHOLD = BigDecimal("1000")

    validates :expense_type, inclusion: { in: :permitted_expense_types }
    validates :budget_record_id, :description, :payment_reference, presence: true, unless: :draft?
    validates :payment_reference, length: { maximum: REFERENCE_LIMIT }
    validate :amounts_valid
    validate :receipts_valid
    validate :overrides_valid
    validate :vat_soft_block, unless: :skip_soft_blocks?
    validate :large_amount_soft_block, unless: :skip_soft_blocks?

    def initialize(attributes = {})
      super
      self.expense_type = Expense::TYPE_REIMBURSEMENT if expense_type.blank?
    end

    def draft?
      ActiveModel::Type::Boolean.new.cast(save_as_draft)
    end

    # Set only by from_actual below (never a permitted parameter on the producer
    # form), so a submitter can't pick the internal From-EUSA type to dodge the
    # receipt, VAT and large-amount rules those exist to enforce on them.
    def internal?
      ActiveModel::Type::Boolean.new.cast(@internal)
    end

    # Anything in the receipts param that is not actually an uploaded file is
    # dropped here rather than reaching #size / #original_filename below (a bare
    # String answers #size but not #read) — see ReceiptContentType.uploads_from.
    def receipts
      ReceiptContentType.uploads_from(@receipts)
    end

    # Every uploaded receipt, vetted and normalised once (a HEIC photo is
    # converted to JPEG here, not on attach) so the validation and the
    # controller's attach step agree on exactly the same bytes and filename.
    def receipt_intakes
      @receipt_intakes ||= receipts.map { |file| ReceiptIntake.from_upload(file) }
    end

    # The receipts that passed, as attach_receipt! keyword hashes. Only ever
    # read after #valid?, which is what reports the ones that didn't.
    def usable_receipts
      receipt_intakes.select(&:ok?).map(&:to_attachment)
    end

    # Edit doesn't force a re-upload; create requires at least one receipt.
    def require_receipts?
      @require_receipts.nil? || ActiveModel::Type::Boolean.new.cast(@require_receipts)
    end

    def amount_decimal
      parse_decimal(amount)
    end

    def amount_excl_vat_decimal
      parse_decimal(amount_excl_vat)
    end

    # True when the submission looks like it lacks a VAT breakdown: the ex-VAT
    # amount isn't below the total.
    def vat_missing?
      amount_decimal.present? && amount_excl_vat_decimal.present? &&
        amount_excl_vat_decimal >= amount_decimal
    end

    def large_amount?
      amount_decimal.present? && amount_decimal >= LARGE_AMOUNT_THRESHOLD
    end

    # Attributes for Store#create_expense!.
    def create_attrs(person_record_id)
      update_attrs.merge(person_record_id: person_record_id)
    end

    # Attributes for Store#update_expense!. Overrides are written as empty
    # strings (not nil) so clearing them actually clears the stored value
    # instead of being compacted away; the status write is what promotes a
    # draft on submission (or files it back as a draft).
    def update_attrs
      {
        status: draft? ? Status::DRAFT : Status::PENDING,
        budget_record_id: budget_record_id.presence,
        amount: amount_decimal,
        amount_excl_vat: amount_excl_vat_decimal,
        description: description.to_s.strip,
        payment_reference: payment_reference.to_s.strip,
        expense_type: expense_type,
        payee_name_override: payee_name_override.to_s.strip,
        sort_code_override: BankDetails.format_sort_code(sort_code_override.to_s.strip),
        account_number_override: BankDetails.normalize_account_number(account_number_override.to_s.strip)
      }
    end

    def self.from_expense(expense)
      new(
        expense_type: expense.expense_type,
        amount: expense.amount&.to_s("F"),
        amount_excl_vat: expense.amount_excl_vat&.to_s("F"),
        budget_record_id: expense.budget&.record_id,
        description: expense.description,
        payment_reference: expense.payment_reference,
        payee_name_override: expense.payee_name_override,
        sort_code_override: expense.sort_code_override,
        account_number_override: expense.account_number_override,
        require_receipts: false
      )
    end

    # Pre-fills the finance form that turns an imported EUSA ledger row into a
    # From-EUSA expense: a cost EUSA levied on us directly (a utility, a staff
    # recharge), so there is no receipt, no VAT breakdown and no submitter. The
    # operator still picks the budget.
    def self.from_actual(actual)
      new(
        expense_type: Expense::TYPE_FROM_EUSA,
        internal: true,
        amount: actual.debit&.to_s("F"),
        amount_excl_vat: actual.debit&.to_s("F"),
        description: actual.narrative.to_s.strip,
        payment_reference: actual.ref.to_s.strip[0, REFERENCE_LIMIT],
        require_receipts: false
      )
    end

    private

    def permitted_expense_types
      internal? ? Expense::TYPES : Expense::SUBMITTER_TYPES
    end

    # A From-EUSA line records an already-settled cost with no receipt and no
    # itemised VAT: the submitter-facing soft blocks have nothing to protect.
    def skip_soft_blocks?
      draft? || internal?
    end

    # Accepts "£1,234.56" (comma thousands) and "12,50" (comma decimal —
    # common for international students; naively stripping the comma would
    # record a 100x amount). Lives in AmountParser so the finance-side budget
    # forms read an amount identically; a blank or unreadable value is nil here
    # and the amounts_valid validation reports it.
    def parse_decimal(value)
      AmountParser.parse(value)
    end

    def amounts_valid
      if draft?
        errors.add(:amount, "must be a positive amount.") if amount.present? && (amount_decimal.nil? || amount_decimal <= 0)
        return
      end

      errors.add(:amount, "must be a positive amount.") if amount_decimal.nil? || amount_decimal <= 0

      if amount_excl_vat_decimal.nil?
        errors.add(:amount_excl_vat, "must be filled in. Copy it from the receipt, or use the " \
                                     "total if no VAT is shown.")
      elsif amount_decimal.present? && amount_excl_vat_decimal > amount_decimal
        errors.add(:amount_excl_vat, "can't be more than the total amount.")
      end
    end

    def receipts_valid
      receipt_intakes.reject(&:ok?).each { |intake| errors.add(:receipts, intake.error) }

      return if draft? || internal? || receipts.any? || expense_receipt_count.to_i.positive?

      if require_receipts?
        # Create: the form has its own file input to hang the error on.
        errors.add(:receipts, "are required. Please attach at least one receipt or invoice.")
      else
        # Edit: uploads live in the receipts gallery, not the form.
        errors.add(:base, "This claim needs at least one receipt. Add one in the " \
                          "receipts section above, then submit.")
      end
    end

    def overrides_valid
      # Length first: the model caps this too (so the ciphertext fits its column),
      # and without a form-level check an over-long invoice-mode prefill would
      # reach store.create_expense! and raise RecordInvalid instead of re-rendering
      # the form with a fixable error.
      if payee_name_override.to_s.length > BankDetails::PAYEE_NAME_MAX_LENGTH
        errors.add(:payee_name_override, BankDetails::PAYEE_NAME_HINT)
      end
      if sort_code_override.present? && !BankDetails.valid_sort_code?(sort_code_override)
        errors.add(:sort_code_override, BankDetails::SORT_CODE_HINT)
      end
      if account_number_override.present? && !BankDetails.valid_account_number?(account_number_override)
        errors.add(:account_number_override, BankDetails::ACCOUNT_NUMBER_HINT)
      end

      if BankDetails.overrides_incomplete?(payee_name_override, sort_code_override, account_number_override)
        errors.add(:base, "To pay a third party, fill in all three: payee name, sort code, " \
                          "and account number, not just one or two.")
      elsif invoice_without_payee?
        errors.add(:base, "An Invoice is paid straight to the supplier, so it needs their payee " \
                          "account name, sort code and account number below. If you paid this " \
                          "bill yourself and want the money back, change the type to " \
                          "Reimbursement instead.")
      end
    end

    # EffectivePayee falls back to the SUBMITTER's own bank details, so an
    # Invoice with no trio pays the producer for a bill they never paid — and
    # review can't catch it, because that fallback satisfies its "no bank
    # details" block just as a real payee would. Checked here rather than as a
    # presence rule per field so a partly-filled trio reports the
    # all-or-nothing message once (above) instead of both.
    def invoice_without_payee?
      expense_type == Expense::TYPE_INVOICE && !draft? &&
        BankDetails.overrides_missing?(payee_name_override, sort_code_override,
                                       account_number_override)
    end

    def vat_soft_block
      return unless vat_missing?
      return if ActiveModel::Type::Boolean.new.cast(vat_acknowledged)

      errors.add(:vat_acknowledged, "is required here: this receipt doesn't seem to itemise VAT, " \
                                    "so we have to deduct the FULL amount from your budget (with " \
                                    "a VAT receipt we'd only deduct the ex-VAT amount). Tick the " \
                                    "box to submit anyway, or ask the seller for a VAT receipt " \
                                    "first: it's in your own interest.")
    end

    def large_amount_soft_block
      return unless large_amount?
      return if ActiveModel::Type::Boolean.new.cast(large_amount_acknowledged)

      errors.add(:large_amount_acknowledged, "is required for a claim this large. Double-check the " \
                                             "amount is right (a common slip is typing pence as " \
                                             "pounds), then tick the box to confirm.")
    end
  end
end
