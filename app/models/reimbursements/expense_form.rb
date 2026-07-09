module Reimbursements
  ##
  # Form object for submitting/editing an expense. Mirrors the Airtable form's
  # required fields exactly — the portal must not be a way around them.
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
                  :vat_itemised, :vat_acknowledged
    attr_writer :receipts, :require_receipts

    validates :expense_type, inclusion: { in: Expense::SUBMITTER_TYPES }
    validates :budget_record_id, :description, :payment_reference, presence: true
    validates :payment_reference, length: { maximum: REFERENCE_LIMIT }
    validate :amounts_valid
    validate :receipts_valid
    validate :overrides_valid
    validate :vat_soft_block

    def initialize(attributes = {})
      super
      self.expense_type = Expense::TYPE_REIMBURSEMENT if expense_type.blank?
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
      update_attrs.merge(person_record_id: person_record_id, status: Status::PENDING)
    end

    # Attributes for Store#update_expense! (no status/person changes).
    def update_attrs
      {
        budget_record_id: budget_record_id,
        amount: amount_decimal,
        amount_excl_vat: amount_excl_vat_decimal,
        description: description.to_s.strip,
        payment_reference: payment_reference.to_s.strip,
        expense_type: expense_type,
        payee_name_override: payee_name_override.presence,
        sort_code_override: formatted_sort_code_override,
        account_number_override: account_number_override.presence&.gsub(/\s/, "")
      }
    end

    # Sort codes are stored dashed ("80-22-60"), matching the payee registry.
    def formatted_sort_code_override
      digits = sort_code_override.to_s.gsub(/[-\s]/, "")
      return sort_code_override.presence if digits.length != 6

      digits.scan(/\d{2}/).join("-")
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

    def parse_decimal(value)
      cleaned = value.to_s.gsub(/[£,\s]/, "")
      return nil if cleaned.blank?

      BigDecimal(cleaned)
    rescue ArgumentError
      nil
    end

    def amounts_valid
      errors.add(:amount, "must be a positive amount.") if amount_decimal.nil? || amount_decimal <= 0

      if amount_excl_vat_decimal.nil?
        errors.add(:amount_excl_vat, "must be filled in. Copy it from the receipt, or use the " \
                                     "total if no VAT is shown.")
      elsif amount_decimal.present? && amount_excl_vat_decimal > amount_decimal
        errors.add(:amount_excl_vat, "can't be more than the total amount.")
      end
    end

    def receipts_valid
      errors.add(:receipts, "are required. Please attach at least one receipt or invoice.") if require_receipts? && receipts.empty?

      receipts.each do |file|
        unless ALLOWED_RECEIPT_TYPES.include?(file.content_type)
          errors.add(:receipts, "#{file.original_filename} must be a PDF or a photo (JPEG/PNG/WEBP).")
        end
        errors.add(:receipts, "#{file.original_filename} must be 5 MB or smaller.") if file.size > MAX_RECEIPT_BYTES
      end
    end

    def overrides_valid
      if sort_code_override.present? && !sort_code_override.gsub(/[-\s]/, "").match?(/\A\d{6}\z/)
        errors.add(:sort_code_override, "must be 6 digits, e.g. 80-22-60.")
      end
      if account_number_override.present? && !account_number_override.gsub(/\s/, "").match?(/\A\d{8}\z/)
        errors.add(:account_number_override, "must be 8 digits.")
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
