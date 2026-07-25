# == Schema Information
#
# Table name: reimbursements_batches
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  date_sent                   :date
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
  # There is no eusa_draft_created column: a present draft_message_id means
  # the draft exists. Legacy batches imported from before the message id was
  # stored have date_sent set — a sent batch necessarily had its draft — so the
  # predicate folds that in.
  class Batch < ApplicationRecord
    include RecordId
    has_many :expenses, class_name: "Reimbursements::Expense",
                        dependent: :nullify, inverse_of: :batch

    validates :name, presence: true

    # BatchProcessor never sends a name, and the historical batches were named
    # after the date they were sent, so derive it the same way.
    before_validation -> { self.name = date_sent.to_s if name.blank? && date_sent.present? }

    def eusa_draft_created
      draft_message_id.present? || date_sent.present?
    end
    alias eusa_draft_created? eusa_draft_created
  end
end
