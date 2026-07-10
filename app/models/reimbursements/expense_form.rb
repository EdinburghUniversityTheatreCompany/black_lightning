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
                  :vat_itemised, :vat_acknowledged, :save_as_draft
    attr_writer :receipts, :require_receipts

    validates :expense_type, inclusion: { in: Expense::SUBMITTER_TYPES }
    validates :budget_record_id, :description, :payment_reference, presence: true, unless: :draft?
    validates :payment_reference, length: { maximum: REFERENCE_LIMIT }
    validate :amounts_valid
    validate :receipts_valid
    validate :overrides_valid
    validate :vat_soft_block, unless: :draft?

    def initialize(attributes = {})
      super
      self.expense_type = Expense::TYPE_REIMBURSEMENT if expense_type.blank?
    end

    def draft?
      ActiveModel::Type::Boolean.new.cast(save_as_draft)
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

    private

    # Accepts "£1,234.56" (comma thousands) and "12,50" (comma decimal —
    # common for international students; naively stripping the comma would
    # record a 100x amount).
    def parse_decimal(value)
      cleaned = value.to_s.gsub(/[£\s]/, "")
      return nil if cleaned.blank?

      cleaned = if cleaned.match?(/,\d{1,2}\z/) && cleaned.exclude?(".")
        cleaned.tr(",", ".")
      else
        cleaned.delete(",")
      end
      BigDecimal(cleaned)
    rescue ArgumentError
      nil
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
      if require_receipts? && !draft? && receipts.empty?
        errors.add(:receipts, "are required. Please attach at least one receipt or invoice.")
      end

      receipts.each do |file|
        unless ALLOWED_RECEIPT_TYPES.include?(file.content_type)
          errors.add(:receipts, "#{file.original_filename} must be a PDF or a photo (JPEG/PNG/WEBP).")
        end
        errors.add(:receipts, "#{file.original_filename} must be 5 MB or smaller.") if file.size > MAX_RECEIPT_BYTES
      end
    end

    def overrides_valid
      if sort_code_override.present? && !BankDetails.valid_sort_code?(sort_code_override)
        errors.add(:sort_code_override, BankDetails::SORT_CODE_HINT)
      end
      if account_number_override.present? && !BankDetails.valid_account_number?(account_number_override)
        errors.add(:account_number_override, BankDetails::ACCOUNT_NUMBER_HINT)
      end
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
  end
end
