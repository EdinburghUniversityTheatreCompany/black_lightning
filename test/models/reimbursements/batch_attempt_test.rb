require "test_helper"

module Reimbursements
  class BatchAttemptTest < ActiveSupport::TestCase
    def cost_centre
      CostCentre.default
    end

    def build_attempt(**attrs)
      BatchAttempt.create!(cost_centre: cost_centre, bacs_date: Date.new(2026, 7, 17), **attrs)
    end

    test "starts as building and resolves to an outcome" do
      attempt = build_attempt

      assert attempt.building?
      attempt.resolve!(status: "completed", batch_record_id: "recBat1")

      assert attempt.reload.completed?
      assert_equal "recBat1", attempt.batch_record_id
      assert_nil attempt.error_messages
    end

    test "rejects an unknown status" do
      attempt = build_attempt
      assert_raises(ActiveRecord::RecordInvalid) { attempt.resolve!(status: "exploded") }
    end

    test "a building attempt goes stale after the concurrency window" do
      fresh = build_attempt
      assert_not fresh.stale?

      travel_to (BatchAttempt::STALE_AFTER + 1.minute).from_now do
        assert fresh.stale?, "an unresolved build older than the job's lock window is stale"
      end

      fresh.resolve!(status: "completed")
      travel_to (BatchAttempt::STALE_AFTER + 1.minute).from_now do
        assert_not fresh.stale?, "only building attempts can be stale"
      end
    end

    test "needing_attention includes everything except a clean completion" do
      building = build_attempt
      failed = build_attempt(status: "failed", error_messages: "boom")
      noop = build_attempt(status: "nothing_to_build")
      with_warnings = build_attempt(status: "completed", error_messages: "SharePoint upload failed")
      clean = build_attempt(status: "completed")

      attention = BatchAttempt.needing_attention

      assert_includes attention, building
      assert_includes attention, failed
      assert_includes attention, noop
      assert_includes attention, with_warnings
      assert_not_includes attention, clean
    end
  end
end
