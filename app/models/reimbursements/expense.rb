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
#  description             :text(65535)
#  expense_type            :string(255)      default("Reimbursement"), not null
#  nominal_code_override   :string(255)
#  payee_name_override     :text(65535)
#  payment_confirmed_date  :date
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
  # An expense submission: predicates, the effective_* money-path helpers and
  # the receipts wrapper.
  #
  # person/budget/batch may be nil: email-in submissions arrive with gaps the
  # submitter fills later.
  class Expense < ApplicationRecord
    include RecordId
    include EffectivePayee
    include ExpenseSemantics

    TYPE_REIMBURSEMENT = "Reimbursement".freeze
    TYPE_INVOICE = "Invoice".freeze
    TYPE_FROM_EUSA = "From EUSA (utility, staff cost, etc)".freeze
    TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE, TYPE_FROM_EUSA ].freeze
    # "From EUSA" is internal bookkeeping; submitters only pick between these.
    SUBMITTER_TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE ].freeze

    # Third-party "pay a supplier directly" bank details, encrypted at rest.
    # Non-deterministic (the default) — the money path reads the
    # decrypted attributes via EffectivePayee; nothing queries by value.
    # support_unencrypted_data (config/application.rb) keeps pre-encryption
    # plaintext rows readable until the backfill runs.
    encrypts :sort_code_override
    encrypts :account_number_override
    encrypts :payee_name_override

    # Column fit for the encrypted trio. Rails' own auto-injected
    # validate_column_size guard is switched off in config/application.rb because
    # it measures the DECRYPTED value against the column limit — the wrong value
    # — so these explicit plaintext caps are what actually keeps the ciphertext
    # inside its column. payee_name_override lives in a TEXT column (widened for
    # exactly this reason) and the digit fields in string(255).
    validates :payee_name_override, length: { maximum: BankDetails::PAYEE_NAME_MAX_LENGTH }
    validates :sort_code_override, :account_number_override,
              length: { maximum: BankDetails::BANK_DIGITS_MAX_LENGTH }

    belongs_to :person, class_name: "Reimbursements::Person", optional: true, inverse_of: :expenses
    belongs_to :budget, class_name: "Reimbursements::Budget", optional: true, inverse_of: :expenses
    belongs_to :batch, class_name: "Reimbursements::Batch", optional: true, inverse_of: :expenses
    belongs_to :financial_year, class_name: "Reimbursements::FinancialYear", optional: true

    # Receipts. The reader below wraps these into Attachment POROs so views
    # and services keep calling receipt.attachment_id / .url / .preview_url.
    has_many_attached :receipt_files

    has_many :eusa_actuals, class_name: "Reimbursements::EusaActual",
                            dependent: :nullify, inverse_of: :expense

    validates :status, inclusion: { in: Status.all }
    validates :expense_type, inclusion: { in: TYPES }

    # auto_number backs the human-facing "Expense #N" label. It continues from
    # the highest number on record rather than tracking the PK, so the numbers
    # imported with the historical claims are never handed out twice.
    before_create lambda {
      self.auto_number ||= (self.class.maximum(:auto_number) || 0) + 1
      self.submitted_at ||= Time.current
    }

    # AR's own reader would return the integer FK; the PORO returned the
    # linked batch's record id STRING, compared against batch.record_id in
    # the batches controller. Same for budget_id/person_id below — the Store
    # and OwnerEndorsement flows pass them around as opaque strings.
    def batch_id = self[:batch_id]&.to_s
    def budget_record_id = self[:budget_id]&.to_s
    def person_record_id = self[:person_id]&.to_s

    # One SharePoint URL per line in the column; the PORO exposed an Array.
    def sharepoint_receipt_urls
      self[:sharepoint_receipt_urls].to_s.split("\n").map(&:strip).compact_blank
    end

    # Attached files wrapped back into the Attachment PORO.
    #
    # Every URL points at Admin::Reimbursements::ReceiptFilesController, which
    # re-checks who is asking, and never at ActiveStorage's own routes, which
    # are unauthenticated and permanent by design. attachment_id is therefore
    # the BLOB ID rather than the blob's signed id: the signed id is a bearer
    # token for those routes, so emitting one in the markup — which the remove
    # button did — would leave the permanent link this replaced. A bare id is
    # useless without a session, and the controller only ever resolves it
    # within the claim in the URL.
    #
    # URLs are path-only, so no host configuration is needed.
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
        size_bytes: file.byte_size,
        content_type: file.content_type.to_s,
        thumbnail_url: (helpers.thumbnail_admin_reimbursements_expense_receipt_path(*ids) if file.representable?),
        download_url: helpers.download_admin_reimbursements_expense_receipt_path(*ids),
        blob: file.blob
      )
    end
  end
end
