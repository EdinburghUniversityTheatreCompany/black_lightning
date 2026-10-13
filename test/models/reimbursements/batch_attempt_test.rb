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

    test "records whether the build made its EUSA draft, and an older attempt has no record" do
      drafted = build_attempt
      drafted.resolve!(status: "failed", error_messages: "ORPHAN DRAFT",
                       draft_web_link: "https://outlook.example/draft-1")
      undrafted = build_attempt
      undrafted.resolve!(status: "failed", error_messages: "EUSA draft creation failed",
                         draft_web_link: BatchAttempt::NO_DRAFT)
      older = build_attempt(status: "failed", error_messages: "boom")

      assert_predicate drafted.reload, :made_draft?
      assert_equal "https://outlook.example/draft-1", drafted.draft_web_link
      assert_not undrafted.reload.made_draft?
      assert_not undrafted.draft_unknown?, "a recorded none must survive the round trip as blank, not nil"
      assert_predicate older, :draft_unknown?
    end

    test "keeps a draft link longer than a string column holds" do
      link = "https://outlook.office365.com/owa/?ItemID=#{'A' * 400}&exvsurl=1&viewmodel=ReadMessageItem"
      attempt = build_attempt

      attempt.resolve!(status: "failed", error_messages: "ORPHAN DRAFT", draft_web_link: link)

      assert_equal link, attempt.reload.draft_web_link
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
      # A serialised double-click's no-op is expected: recorded, not alerted on.
      assert_not_includes attention, noop
    end

    test "dismissing hides the alert without editing the record" do
      failed = build_attempt(status: "failed", error_messages: "boom",
                             batch_record_id: "recBat9")
      failed.dismiss!(email: "finance@example.com")
      failed.reload

      assert_not_nil failed.dismissed_at
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
