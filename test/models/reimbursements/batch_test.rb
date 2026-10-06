require "test_helper"

module Reimbursements
  class BatchTest < ActiveSupport::TestCase
    test "eusa_draft_created derives from the draft message id or a sent date" do
      assert_not Batch.create!(name: "fresh").eusa_draft_created
      assert Batch.create!(name: "drafted", draft_message_id: "AAMkAG=").eusa_draft_created
      # Legacy imported batches predate draft_message_id but were sent.
      assert Batch.create!(name: "legacy", date_sent: Date.new(2026, 5, 1)).eusa_draft_created
    end
  end
end
