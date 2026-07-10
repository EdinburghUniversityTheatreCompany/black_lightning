module Reimbursements
  ##
  # A batch of expenses submitted to EUSA in one BACS request, from the Airtable
  # Batches table. PORO boundary type mirroring bedlam-bacs' Batch dataclass.
  class Batch
    attr_reader :record_id, :name, :date_sent, :sharepoint_backup_url,
                :eusa_draft_created, :producer_notifications_sent, :notes

    def initialize(record_id:, name:, date_sent: nil, sharepoint_backup_url: "",
                   eusa_draft_created: false, producer_notifications_sent: false, notes: "")
      @record_id = record_id
      @name = name
      @date_sent = date_sent
      @sharepoint_backup_url = sharepoint_backup_url
      @eusa_draft_created = eusa_draft_created
      @producer_notifications_sent = producer_notifications_sent
      @notes = notes
    end
  end
end
