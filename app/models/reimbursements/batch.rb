# == Schema Information
#
# Table name: reimbursements_batches
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  date_sent                   :date
#  draft_web_link              :text(65535)
#  name                        :string(255)      default(""), not null
#  notes                       :text(65535)
#  producer_notifications_sent :boolean          default(FALSE), not null
#  sharepoint_backup_url       :text(65535)
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  airtable_record_id          :string(255)
#  draft_message_id            :string(255)
#
# Indexes
#
#  index_reimbursements_batches_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_batches_on_draft_message_id    (draft_message_id)
#
module Reimbursements
  ##
  # A batch of expenses submitted to EUSA in one BACS request.
  #
  # There is no eusa_draft_created column: a draft_message_id means the draft
  # exists, and legacy batches, which predate the id, have a date_sent instead.
  class Batch < ApplicationRecord
    include RecordId
    has_many :expenses, class_name: "Reimbursements::Expense",
                        dependent: :nullify, inverse_of: :batch

    validates :name, presence: true

    # BatchProcessor sends no name; historical batches were named after their date.
    before_validation -> { self.name = date_sent.to_s if name.blank? && date_sent.present? }

    def eusa_draft_created
      draft_message_id.present? || date_sent.present?
    end
    alias eusa_draft_created? eusa_draft_created
  end
end
