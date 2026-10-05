module Reimbursements
  ##
  # Form object for submitting/editing an expense. Submitting enforces every
  # field finance requires; a DRAFT relaxes the presence rules but still checks
  # the format of whatever was filled in.
  #
  # The VAT rule is a SOFT block: when the ex-VAT amount isn't below the total,
  # submitters must tick an acknowledgement, because the full amount then counts
  # against their budget, but they can always submit.
  class ExpenseForm
    include ActiveModel::Model

    # What a receipt may be STORED as.
    ALLOWED_RECEIPT_TYPES = %w[application/pdf image/jpeg image/png image/webp].freeze
    # iOS photographs default to HEIC; ReceiptIntake converts them to JPEG.
    CONVERTED_RECEIPT_TYPES = %w[image/heic image/heif].freeze
    ACCEPTED_RECEIPT_TYPES = (ALLOWED_RECEIPT_TYPES + CONVERTED_RECEIPT_TYPES).freeze
    # Extensions as well as types: browsers vary in which they match a HEIC
    # file against.
    RECEIPT_ACCEPT_ATTRIBUTE = (ACCEPTED_RECEIPT_TYPES + %w[.heic .heif]).join(",").freeze
    MAX_RECEIPT_BYTES = 5.megabytes # per-receipt upload cap; a batch mails them all as attachments
    REFERENCE_LIMIT = 18 # EUSA truncates payment references beyond this

    attr_accessor :expense_type, :amount, :amount_excl_vat, :budget_record_id,
                  :description, :payment_reference, :payee_name_override,
                  :sort_code_override, :account_number_override,
                  :vat_acknowledged, :save_as_draft,
                  :large_amount_acknowledged, :expense_receipt_count,
                  :payment_method, :foreign_amount, :foreign_currency,
                  :iban_override, :bic_override
    attr_writer :receipts, :require_receipts, :internal, :settled, :offerable_budget_ids

    # At or above this, submitting asks for a tick: the usual slip is pence
    # typed as pounds.
    LARGE_AMOUNT_THRESHOLD = BigDecimal("1000")

    validates :expense_type, inclusion: { in: :permitted_expense_types }
    validates :payment_method, inclusion: { in: Expense::PAYMENT_METHODS }
    validates :budget_record_id, :description, :payment_reference, presence: true, unless: :draft?
    validates :payment_reference, length: { maximum: REFERENCE_LIMIT }
    validate :amounts_valid
    validate :receipts_valid
    validate :overrides_valid
    validate :budget_still_offerable
    validate :vat_soft_block, unless: :skip_soft_blocks?
    validate :large_amount_soft_block, unless: :skip_soft_blocks?

    def initialize(attributes = {})
      super
      self.expense_type = Expense::TYPE_REIMBURSEMENT if expense_type.blank?
      self.payment_method = Expense::PAYMENT_METHOD_UK_BACS if payment_method.blank?
      self.foreign_currency = Expense::CURRENCY_EUR if foreign_currency.blank?
    end

    def international?
      payment_method == Expense::PAYMENT_METHOD_INTERNATIONAL
    end

    def foreign_amount_decimal
      parse_decimal(foreign_amount)
    end

    def draft?
      ActiveModel::Type::Boolean.new.cast(save_as_draft)
    end

    # The budget ids the controller rendered into the picker, as strings. nil
    # means no picker was drawn (ExpenseImport, from_actual), so the choice is
    # not second-guessed.
    def offerable_budget_ids
      @offerable_budget_ids&.map(&:to_s)
    end

    # Validated against the list RENDERED, which catches a budget deleted or
    # deactivated while the form was open.
    def stale_budget?
      offered = offerable_budget_ids
      return false if offered.nil? || budget_record_id.blank?

      offered.exclude?(budget_record_id.to_s)
    end

    # Read by the controller so the notice says the budget was dropped.
    def dropped_stale_budget?
      draft? && stale_budget?
    end

    # Set only by from_actual, never a permitted param, so a submitter can't
    # pick From EUSA to dodge the receipt, VAT and large-amount rules.
    def internal?
      ActiveModel::Type::Boolean.new.cast(@internal)
    end

    # Set only by ExpenseImport, for money that has already moved. Suppresses
    # the two payee blocks and nothing else: Build Batch reads Approved claims
    # alone, so a settled claim never reaches the money path they protect.
    def settled?
      ActiveModel::Type::Boolean.new.cast(@settled)
    end

    # Drops anything that is not an uploaded file (a bare String answers #size
    # but not #read).
    def receipts
      ReceiptContentType.uploads_from(@receipts)
    end

    # Vetted once, so validation and the attach step agree on the same bytes.
    def receipt_intakes
      @receipt_intakes ||= receipts.map { |file| ReceiptIntake.from_upload(file) }
    end

    # As attach_receipt! keyword hashes; read only after #valid?.
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

    # The ex-VAT amount isn't below the total.
    def vat_missing?
      amount_decimal.present? && amount_excl_vat_decimal.present? &&
        amount_excl_vat_decimal >= amount_decimal
    end

    # Reads the figure the submitter typed: the foreign amount on the
    # international rail. A fat-finger guard, so the sterling threshold is
    # close enough.
    def large_amount?
      typed = international? ? foreign_amount_decimal : amount_decimal
      typed.present? && typed >= LARGE_AMOUNT_THRESHOLD
    end

    # Attributes for Store#create_expense!.
    def create_attrs(person_record_id)
      update_attrs.merge(person_record_id: person_record_id)
    end

    # Attributes for Store#update_expense!. Overrides are written as empty
    # strings, not nil, so clearing them clears the stored value.
    def update_attrs
      {
        status: draft? ? Status::DRAFT : Status::PENDING,
        budget_record_id: (budget_record_id.presence unless stale_budget?),
        amount: amount_decimal,
        amount_excl_vat: amount_excl_vat_decimal,
        description: description.to_s.strip,
        payment_reference: payment_reference.to_s.strip,
        expense_type: expense_type,
        payee_name_override: payee_name_override.to_s.strip,
        sort_code_override: BankDetails.format_sort_code(sort_code_override.to_s.strip),
        account_number_override: BankDetails.normalize_account_number(account_number_override.to_s.strip),
        payment_method: payment_method,
        foreign_amount: foreign_amount_decimal,
        # International only: a code beside a GBP amount reads as a claim about it.
        foreign_currency: (foreign_currency.to_s.strip.upcase.presence if international?),
        iban_override: BankDetails.normalize_iban(iban_override.to_s.strip),
        bic_override: BankDetails.normalize_bic(bic_override.to_s.strip)
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
        payment_method: expense.payment_method,
        foreign_amount: expense.foreign_amount&.to_s("F"),
        foreign_currency: expense.foreign_currency,
        iban_override: expense.iban_override,
        bic_override: expense.bic_override,
        require_receipts: false
      )
    end

    # Prefills a From-EUSA expense from an imported ledger row: a cost EUSA
    # levied directly, with no receipt, VAT breakdown or submitter.
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

    def skip_soft_blocks?
      draft? || internal?
    end

    def parse_decimal(value)
      AmountParser.parse(value)
    end

    def amounts_valid
      if draft?
        errors.add(:amount, "must be a positive amount.") if amount.present? && (amount_decimal.nil? || amount_decimal <= 0)
        if foreign_amount.present? && (foreign_amount_decimal.nil? || foreign_amount_decimal <= 0)
          errors.add(:foreign_amount, "must be a positive amount.")
        end
        return
      end

      return international_amounts_valid if international?

      errors.add(:amount, "must be a positive amount.") if amount_decimal.nil? || amount_decimal <= 0

      if amount_excl_vat_decimal.nil?
        errors.add(:amount_excl_vat, "must be filled in. Copy it from the receipt, or use the " \
                                     "total if no VAT is shown.")
      elsif amount_decimal.present? && amount_excl_vat_decimal > amount_decimal
        errors.add(:amount_excl_vat, "can't be more than the total amount.")
      end
    end

    # Only the foreign amount: finance enters the GBP figure at review and
    # cannot approve without it. Expense mirrors ex-VAT from gross.
    def international_amounts_valid
      unless Expense::FOREIGN_CURRENCIES.include?(foreign_currency.to_s.strip.upcase)
        errors.add(:foreign_currency, "must be one of the currencies listed.")
      end
      return if foreign_amount_decimal.present? && foreign_amount_decimal.positive?

      errors.add(:foreign_amount, "must be a positive amount, as printed on the invoice.")
    end

    # Refusing the submit keeps the producer's typing, where the foreign key
    # raising would lose the claim (Honeybadger 134234926). A DRAFT is exempt:
    # #update_attrs drops the stale id and it saves.
    def budget_still_offerable
      return if draft? || !stale_budget?

      errors.add(:budget_record_id, "is no longer available. The finance team removed or " \
                                    "retired it while you were filling this in. Everything else " \
                                    "you typed has been kept: pick another budget and submit again.")
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
      # Length first, so an over-long name re-renders the form instead of
      # raising RecordInvalid on the model's own cap.
      if payee_name_override.to_s.length > BankDetails::PAYEE_NAME_MAX_LENGTH
        errors.add(:payee_name_override, BankDetails::PAYEE_NAME_HINT)
      end
      international? ? international_overrides_valid : uk_overrides_valid
    end

    def uk_overrides_valid
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

    # The IBAN is mod-97 checked: this is the last look before EUSA's bank acts.
    def international_overrides_valid
      errors.add(:iban_override, BankDetails::IBAN_HINT) if iban_override.present? && !BankDetails.valid_iban?(iban_override)
      errors.add(:bic_override, BankDetails::BIC_HINT) if bic_override.present? && !BankDetails.valid_bic?(bic_override)

      if BankDetails.overrides_incomplete?(payee_name_override, iban_override, bic_override)
        errors.add(:base, "To pay someone abroad, fill in all three: payee name, IBAN and " \
                          "BIC/SWIFT code, not just one or two.")
      elsif international_without_payee?
        errors.add(:base, "An international payment goes straight to the payee's own bank, so it " \
                          "needs their account name, IBAN and BIC/SWIFT code below.")
      end
    end

    # Every international claim, not only an Invoice: nobody has an IBAN on file.
    def international_without_payee?
      !draft? && !settled? &&
        BankDetails.overrides_missing?(payee_name_override, iban_override, bic_override)
    end

    # EffectivePayee falls back to the submitter's own details, so an Invoice
    # with no trio would pay the producer, and review cannot see it.
    def invoice_without_payee?
      expense_type == Expense::TYPE_INVOICE && !draft? && !settled? &&
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
