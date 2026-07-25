module Reimbursements
  ##
  # Form object for submitting/editing an expense. When submitting, it
  # mirrors the Airtable form's required fields exactly — the portal must not
  # be a way around them. Saving as a DRAFT relaxes the presence rules (like
  # email-in, gaps are completed later); format rules still apply to whatever
  # was filled in, and submitting the draft re-runs the full validation.
  #
  # The VAT rule is a SOFT block: when the receipt doesn't itemise VAT (or the
  # ex-VAT amount equals the total), submitters must tick an acknowledgement,
  # because the full amount then counts against their budget — but they can
  # always submit.
  class ExpenseForm
    include ActiveModel::Model

    ALLOWED_RECEIPT_TYPES = %w[application/pdf image/jpeg image/png image/webp].freeze
    MAX_RECEIPT_BYTES = 5.megabytes # Airtable content-API per-upload limit
    REFERENCE_LIMIT = 18 # EUSA truncates payment references beyond this

    attr_accessor :expense_type, :amount, :amount_excl_vat, :budget_record_id,
                  :description, :payment_reference, :payee_name_override,
                  :sort_code_override, :account_number_override,
                  :vat_itemised, :vat_acknowledged, :save_as_draft,
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

    def receipts
      Array(@receipts).compact_blank
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

    # True when the submission looks like it lacks a VAT breakdown: the
    # extractor said so, or the ex-VAT amount isn't below the total.
    def vat_missing?
      return true if vat_itemised.to_s == "false"

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
    # strings (not nil) so clearing them actually clears the Airtable fields;
    # the status write is what promotes a draft on submission (or files it
    # back as a draft).
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
      receipts.each do |file|
        # Size checked first, before ReceiptContentType reads the whole file
        # into memory to sniff it — an oversized file should never pay that
        # cost just to be rejected for size anyway.
        if file.size > MAX_RECEIPT_BYTES
          errors.add(:receipts, "#{file.original_filename} must be 5 MB or smaller.")
        elsif !ReceiptContentType.allowed_upload?(file)
          errors.add(:receipts, "#{file.original_filename} must be a PDF or a photo (JPEG/PNG/WEBP).")
        end
      end

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
      if sort_code_override.present? && !BankDetails.valid_sort_code?(sort_code_override)
        errors.add(:sort_code_override, BankDetails::SORT_CODE_HINT)
      end
      if account_number_override.present? && !BankDetails.valid_account_number?(account_number_override)
        errors.add(:account_number_override, BankDetails::ACCOUNT_NUMBER_HINT)
      end

      return unless BankDetails.overrides_incomplete?(payee_name_override, sort_code_override, account_number_override)

      errors.add(:base, "To pay a third party, fill in all three: payee name, sort code, " \
                        "and account number — not just one or two.")
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
