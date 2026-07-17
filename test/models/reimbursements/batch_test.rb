require "test_helper"

module Reimbursements
  class BatchTest < ActiveSupport::TestCase
    test "carries batch attributes with sensible defaults" do
      batch = Batch.new(record_id: "recBatch1", name: "BACS 2026-05-13", date_sent: Date.new(2026, 5, 13))
      assert_equal "recBatch1", batch.record_id
      assert_equal "BACS 2026-05-13", batch.name
      assert_equal Date.new(2026, 5, 13), batch.date_sent
      assert_equal "", batch.sharepoint_backup_url
      assert_not batch.eusa_draft_created
      assert_not batch.producer_notifications_sent
    end

    test "records draft and notification flags" do
      batch = Batch.new(record_id: "recBatch1", name: "BACS", eusa_draft_created: true,
        producer_notifications_sent: true, sharepoint_backup_url: "https://sp/backup", notes: "sent")
      assert batch.eusa_draft_created
      assert batch.producer_notifications_sent
      assert_equal "https://sp/backup", batch.sharepoint_backup_url
      assert_equal "sent", batch.notes
    end
  end
end
