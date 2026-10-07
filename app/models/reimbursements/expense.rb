# == Schema Information
#
# Table name: reimbursements_expenses
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  account_number_override :string(255)
#  amount                  :decimal(12, 2)
#  amount_excl_vat         :decimal(12, 2)
#  auto_number             :integer
#  bic_override            :string(255)
#  description             :text(65535)
#  expense_type            :string(255)      default("Reimbursement"), not null
#  foreign_amount          :decimal(12, 2)
#  foreign_currency        :string(255)
#  iban_override           :string(255)
#  import_key              :string(255)
#  nominal_code_override   :string(255)
#  payee_name_override     :text(65535)
#  payment_confirmed_date  :date
#  payment_method          :string(255)      default("uk_bacs"), not null
#  payment_reference       :string(255)
#  producer_notified       :boolean          default(FALSE), not null
#  receipts_offloaded      :boolean          default(FALSE), not null
#  rejection_notified      :datetime
#  rejection_reason        :text(65535)
#  sharepoint_receipt_urls :text(65535)
#  sort_code_override      :string(255)
#  status                  :string(255)      default("Pending"), not null
#  submitted_at            :datetime
#  submitted_to_eusa_date  :date
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  airtable_record_id      :string(255)
#  batch_id                :bigint
#  budget_id               :bigint
#  financial_year_id       :bigint
#  person_id               :bigint
#  source_message_id       :string(255)
#
# Indexes
#
#  index_reimbursements_expenses_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_expenses_on_auto_number         (auto_number) UNIQUE
#  index_reimbursements_expenses_on_batch_id            (batch_id)
#  index_reimbursements_expenses_on_budget_id           (budget_id)
#  index_reimbursements_expenses_on_financial_year_id   (financial_year_id)
#  index_reimbursements_expenses_on_import_key          (import_key) UNIQUE
#  index_reimbursements_expenses_on_person_id           (person_id)
#  index_reimbursements_expenses_on_source_message_id   (source_message_id) UNIQUE
#  index_reimbursements_expenses_on_status              (status)
#
# Foreign Keys
#
#  fk_rails_...  (batch_id => reimbursements_batches.id)
#  fk_rails_...  (budget_id => reimbursements_budgets.id)
#  fk_rails_...  (financial_year_id => reimbursements_financial_years.id)
#  fk_rails_...  (person_id => reimbursements_people.id)
#
module Reimbursements
  ##
  # An expense claim. person/budget/batch may be nil: email-in submissions
  # arrive with gaps the submitter fills later.
  class Expense < ApplicationRecord
    include RecordId
    include EffectivePayee

    TYPE_REIMBURSEMENT = "Reimbursement".freeze
    TYPE_INVOICE = "Invoice".freeze
    TYPE_FROM_EUSA = "From EUSA (utility, staff cost, etc)".freeze
    TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE, TYPE_FROM_EUSA ].freeze
    # "From EUSA" is internal bookkeeping; submitters only pick between these.
    SUBMITTER_TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE ].freeze

    # The rail, not the currency, is the discriminator: an international
    # supplier can invoice in GBP and still need an IBAN.
    PAYMENT_METHOD_UK_BACS = "uk_bacs".freeze
    PAYMENT_METHOD_INTERNATIONAL = "international".freeze
    PAYMENT_METHODS = [ PAYMENT_METHOD_UK_BACS, PAYMENT_METHOD_INTERNATIONAL ].freeze
    PAYMENT_METHOD_OPTIONS = [ [ "UK bank account", PAYMENT_METHOD_UK_BACS ],
                               [ "International (IBAN)", PAYMENT_METHOD_INTERNATIONAL ] ].freeze

    # A fixed list, not free text: a mistyped code is a payment EUSA's bank
    # cannot route. Adding one is a single entry here.
    CURRENCY_EUR = "EUR".freeze
    FOREIGN_CURRENCIES = %w[
      EUR USD GBP CHF SEK NOK DKK PLN CZK CAD AUD NZD JPY
    ].freeze

    # Third-party bank details, non-deterministic: nothing queries by value.
    # support_unencrypted_data is false, so a plaintext value raises.
    encrypts :sort_code_override
    encrypts :account_number_override
    encrypts :payee_name_override
    encrypts :iban_override
    encrypts :bic_override

    # Rails' validate_column_size is off because it measures the decrypted
    # value; these plaintext caps keep the ciphertext inside its column.
    validates :payee_name_override, length: { maximum: BankDetails::PAYEE_NAME_MAX_LENGTH }
    validates :sort_code_override, :account_number_override,
              length: { maximum: BankDetails::BANK_DIGITS_MAX_LENGTH }
    validates :iban_override, length: { maximum: BankDetails::IBAN_MAX_LENGTH }
    validates :bic_override, length: { maximum: BankDetails::BIC_MAX_LENGTH }

    belongs_to :person, class_name: "Reimbursements::Person", optional: true, inverse_of: :expenses
    belongs_to :budget, class_name: "Reimbursements::Budget", optional: true, inverse_of: :expenses
    belongs_to :batch, class_name: "Reimbursements::Batch", optional: true, inverse_of: :expenses
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true

    # Read through #receipts, which wraps them as Attachments.
    has_many_attached :receipt_files

    has_many :eusa_actuals, class_name: "Reimbursements::EusaActual",
                            dependent: :nullify, inverse_of: :expense

    # No cost-centre column: the budget decides which pot pays. nil means
    # "unplaced", never a centre of its own.
    def cost_centre
      budget&.cost_centre
    end

    def cost_centre_id
      budget&.cost_centre_id
    end

    validates :status, inclusion: { in: Status.all }
    validates :expense_type, inclusion: { in: TYPES }
    validates :payment_method, inclusion: { in: PAYMENT_METHODS }
    validates :foreign_currency, inclusion: { in: FOREIGN_CURRENCIES }, allow_blank: true

    # A foreign invoice carries no reclaimable UK VAT, so an international
    # claim's ex-VAT is its gross.
    before_validation lambda {
      self.amount_excl_vat = amount if international?
    }

    # auto_number continues from MAX, not the PK, so imported numbers are
    # never handed out twice.
    before_create lambda {
      self.auto_number ||= (self.class.maximum(:auto_number) || 0) + 1
      self.submitted_at ||= Time.current
    }

    def international? = payment_method == PAYMENT_METHOD_INTERNATIONAL

    def pending? = status == Status::PENDING
    def draft? = status == Status::DRAFT
    def approved? = status == Status::APPROVED
    def rejected? = status == Status::REJECTED

    # Never internal "From EUSA" entries: editing one in the portal would
    # rewrite its type to a submitter type.
    def editable?
      (draft? || pending?) && SUBMITTER_TYPES.include?(expense_type)
    end

    # A zero amount means "not yet known" (.blank? misses it).
    def missing_completion_fields
      missing = []
      missing << "a budget" if budget.nil?
      missing << "the amount" if amount.blank? || amount.zero?
      missing << "the amount excluding VAT" if amount_excl_vat.blank? || amount_excl_vat.zero?
      missing << "a description" if description.blank?
      missing << "a payment reference" if payment_reference.blank?
      # A SharePoint URL stored when the file was offloaded counts as a receipt.
      missing << "a receipt" if receipt_files.empty? && sharepoint_receipt_urls.blank?
      missing
    end

    def needs_completion?
      missing_completion_fields.any?
    end

    # Counts the attachments rather than building #receipts (three route
    # paths per file) for every row; falls back to offloaded SharePoint URLs.
    def receipt_count
      attached = receipt_files.size
      attached.positive? ? attached : sharepoint_receipt_urls.size
    end

    # String ids, compared against record_id by the store and controllers.
    def batch_id = self[:batch_id]&.to_s
    def budget_record_id = self[:budget_id]&.to_s
    def person_record_id = self[:person_id]&.to_s

    # One SharePoint URL per line in the column.
    def sharepoint_receipt_urls
      self[:sharepoint_receipt_urls].to_s.split("\n").map(&:strip).compact_blank
    end

    # URLs point at ReceiptFilesController, never ActiveStorage's permanent,
    # unauthenticated routes. attachment_id is the BLOB id, never the signed
    # id, which is a bearer token for those routes.
    def receipts
      @receipts ||= receipt_files.map { |file| self.class.wrap_receipt(file) }
    end

    def reload(*)
      @receipts = nil
      super
    end

    def self.wrap_receipt(file)
      helpers = Rails.application.routes.url_helpers
      ids = [ file.record_id.to_s, file.blob_id.to_s ]
      Attachment.new(
        attachment_id: file.blob_id.to_s,
        filename: file.filename.to_s,
        url: helpers.inline_admin_reimbursements_expense_receipt_path(*ids),
        content_type: file.content_type.to_s,
        thumbnail_url: (helpers.thumbnail_admin_reimbursements_expense_receipt_path(*ids) if file.representable?),
        download_url: helpers.download_admin_reimbursements_expense_receipt_path(*ids),
        blob: file.blob
      )
    end
  end
end
