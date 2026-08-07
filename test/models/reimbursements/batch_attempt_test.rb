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

    test "needing_attention surfaces building/failed/completed-with-warnings, not clean or nothing_to_build" do
      building = build_attempt
      failed = build_attempt(status: "failed", error_messages: "boom")
      noop = build_attempt(status: "nothing_to_build")
      with_warnings = build_attempt(status: "completed", error_messages: "SharePoint upload failed")
      clean = build_attempt(status: "completed")

      attention = BatchAttempt.needing_attention

      assert_includes attention, building
      assert_includes attention, failed
      assert_includes attention, with_warnings
      assert_not_includes attention, clean
      # A deduped double-click's no-op is benign and expected — recorded, but
      # not surfaced as a lingering alert.
      assert_not_includes attention, noop
    end

    test "a dismissed attempt drops out of needing_attention" do
      failed = build_attempt(status: "failed", error_messages: "boom")

      assert_includes BatchAttempt.needing_attention, failed

      failed.dismiss!(email: "finance@example.com")

      assert_not_includes BatchAttempt.needing_attention, failed
    end

    test "dismissing hides the alert without editing the record" do
      failed = build_attempt(status: "failed", error_messages: "boom",
                             batch_record_id: "recBat9")
      failed.dismiss!(email: "finance@example.com")
      failed.reload

      assert_predicate failed, :dismissed?
      assert_predicate failed, :failed?
      assert_equal "boom", failed.error_messages
      assert_equal "recBat9", failed.batch_record_id
      assert_equal "finance@example.com", failed.dismissed_by_email
    end

    test "dismissing does not disturb another attempt's alert" do
      first = build_attempt(status: "failed", error_messages: "boom")
      second = build_attempt(status: "failed", error_messages: "also boom")

      first.dismiss!

      assert_not_includes BatchAttempt.needing_attention, first
      assert_includes BatchAttempt.needing_attention, second
    end

    test "a build still running is not dismissible, but a stale one is" do
      running = build_attempt

      assert_not running.dismissible?

      travel_to (BatchAttempt::STALE_AFTER + 1.minute).from_now do
        assert_predicate running, :dismissible?
      end
    end

    test "failed, no-op and completed attempts are all dismissible" do
      assert_predicate build_attempt(status: "failed", error_messages: "boom"), :dismissible?
      assert_predicate build_attempt(status: "nothing_to_build"), :dismissible?
      assert_predicate build_attempt(status: "completed", error_messages: "partial"), :dismissible?
    end
  end
end
