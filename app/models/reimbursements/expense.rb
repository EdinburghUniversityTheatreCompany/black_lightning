# == Schema Information
#
# Table name: reimbursements_expenses
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  account_number_override :string(255)
#  ai_check_status         :string(255)      default(""), not null
#  ai_checked_at           :datetime
#  ai_comment              :text(65535)
#  amount                  :decimal(12, 2)
#  amount_excl_vat         :decimal(12, 2)
#  auto_number             :integer
#  description             :text(65535)
#  expense_type            :string(255)      default("Reimbursement"), not null
#  nominal_code_override   :string(255)
#  payee_name_override     :string(255)
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
  # An expense submission. ActiveRecord replacement for the Airtable-era PORO
  # (now Reimbursements::Airtable::Expense), keeping its exact public
  # interface — predicates, effective_* money-path helpers and the receipts
  # wrapper — so controllers, views, jobs and BatchProcessor are untouched.
  #
  # person/budget/batch may be nil: email-in submissions arrive with gaps the
  # submitter fills later.
  class Expense < ApplicationRecord
    include EffectivePayee

    TYPE_REIMBURSEMENT = "Reimbursement".freeze
    TYPE_INVOICE = "Invoice".freeze
    TYPE_FROM_EUSA = "From EUSA (utility, staff cost, etc)".freeze
    TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE, TYPE_FROM_EUSA ].freeze
    # "From EUSA" is internal bookkeeping; submitters only pick between these.
    SUBMITTER_TYPES = [ TYPE_REIMBURSEMENT, TYPE_INVOICE ].freeze

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

    # Continue the Airtable auto-number sequence for the human-facing
    # "Expense #N" label, and stamp submitted_at (Airtable's was an
    # auto-filled created-time field). The importer supplies explicit values.
    before_create lambda {
      self.auto_number ||= (self.class.maximum(:auto_number) || 0) + 1
      self.submitted_at ||= Time.current
    }

    def record_id = id&.to_s

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

    # Attached files wrapped back into the Attachment PORO. attachment_id is
    # the blob signed id (opaque, stable enough for remove-receipt round
    # trips); URLs are path-only so no host configuration is needed.
    def receipts
      receipt_files.map { |file| self.class.wrap_receipt(file) }
    end

    def self.wrap_receipt(file)
      helpers = Rails.application.routes.url_helpers
      Attachment.new(
        attachment_id: file.signed_id,
        filename: file.filename.to_s,
        url: helpers.rails_blob_path(file, only_path: true),
        size_bytes: file.byte_size,
        content_type: file.content_type.to_s,
        thumbnail_url: (helpers.rails_representation_path(
          file.representation(resize_to_limit: [ 512, 512 ]), only_path: true
        ) if file.representable?),
        blob: file.blob
      )
    end

    def pending? = status == Status::PENDING
    def draft? = status == Status::DRAFT
    def approved? = status == Status::APPROVED

    # Submitters may only change an expense before review picks it up, and
    # never internal "From EUSA" bookkeeping entries.
    def editable?
      (draft? || pending?) && SUBMITTER_TYPES.include?(expense_type)
    end

    # Human labels for the required fields still missing on an incomplete
    # (usually email-in) submission. A documented zero amount means "not yet
    # known" — .blank? alone would miss it (0 is truthy in Ruby).
    def missing_completion_fields
      missing = []
      missing << "a budget" if budget.nil?
      missing << "the amount" if amount.blank? || amount.zero?
      missing << "the amount excluding VAT" if amount_excl_vat.blank? || amount_excl_vat.zero?
      missing << "a description" if description.blank?
      missing << "a payment reference" if payment_reference.blank?
      # A receipt counts as present if a file is attached OR a SharePoint URL
      # was stored when it was offloaded during batch processing.
      missing << "a receipt" if receipts.empty? && sharepoint_receipt_urls.blank?
      missing
    end

    def needs_completion?
      missing_completion_fields.any?
    end

    # Attached files if any, otherwise the count of SharePoint URLs stored
    # when the files were offloaded during batch processing.
    def receipt_count
      receipts.any? ? receipts.size : sharepoint_receipt_urls.size
    end

    # True only for a genuine pass/fail verdict — "error" means the checker
    # itself couldn't run and must NOT lock the expense out of a re-check.
    def ai_checked?
      %w[pass fail].include?(ai_check_status)
    end
  end
end
