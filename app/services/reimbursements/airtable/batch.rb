module Reimbursements
  module Airtable
    ##
    # A batch of expenses submitted to EUSA in one BACS request, from the Airtable
    # Batches table. PORO boundary type mirroring bedlam-bacs' Batch dataclass.
    class Batch
      # +draft_message_id+ is the Graph message id of the EUSA draft this batch
      # created, kept so a reopen can delete the stale draft in Outlook.
      # (+eusa_draft_created+ stays for now; it can be dropped in favour of the id
      # at the MySQL cutover.)
      attr_reader :record_id, :name, :date_sent, :sharepoint_backup_url,
                  :eusa_draft_created, :draft_message_id, :producer_notifications_sent, :notes

      def initialize(record_id:, name:, date_sent: nil, sharepoint_backup_url: "",
                     eusa_draft_created: false, draft_message_id: "",
                     producer_notifications_sent: false, notes: "")
        @record_id = record_id
        @name = name
        @date_sent = date_sent
        @sharepoint_backup_url = sharepoint_backup_url
        @eusa_draft_created = eusa_draft_created
        @draft_message_id = draft_message_id
        @producer_notifications_sent = producer_notifications_sent
        @notes = notes
      end
    end
  end
end
