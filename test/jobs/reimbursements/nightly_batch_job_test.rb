require "test_helper"

module Reimbursements
  class NightlyBatchJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    MC = ModulusCheck
    F = ReimbursementsTestHelpers::FIELD_IDS[:expenses]

    # 2026-07-09 is a Thursday (wday 4); fringe's default run-days are [2, 4],
    # so the nightly is due. 2026-07-08 is a Wednesday (not a run-day).
    THURSDAY = Date.new(2026, 7, 9)
    WEDNESDAY = Date.new(2026, 7, 8)

    class FakeChecker
      def check(_sort, _account) = MC::VALID
    end

    # A store whose expenses read raises, standing in for an Airtable outage —
    # drives the nightly's top-level rescue (handle_failure).
    class BoomStore
      def expenses = raise(StandardError, "airtable down")
    end

    FakeNotifier = ReimbursementsTestHelpers::FakeNotifier

    def payee(**attrs)
      airtable_person_record(sort_code: "08-99-99", account_number: "66374958", **attrs)
    end

    def approved_expense(id: "recApp", ai_status: "pass", **overrides)
      airtable_expense_record(id: id, status: "Approved",
                              overrides: { F[:ai_check_status] => ai_status }.merge(overrides))
    end

    def pending_expense(id: "recPend", days_ago: 5)
      airtable_expense_record(id: id, status: "Pending",
                              overrides: { F[:submitted_at] => (THURSDAY.to_time(:utc) - days_ago.days).iso8601 })
    end

    def stock_store(expenses)
      @store, @client = build_fake_store(
        people: [ payee ], budgets: [ airtable_budget_record ], expenses: expenses
      )
      NightlyBatchJob.store_builder = -> { @store }
    end

    setup do
      @notifier = FakeNotifier.new
      NightlyBatchJob.checker_builder = -> { FakeChecker.new }
      NightlyBatchJob.graph_builder = -> { Object.new }
      # Capture the mailbox the notifier is built for so a test can assert the
      # operator alerts send from the cost centre's send mailbox.
      NightlyBatchJob.notifier_builder = lambda do |mailbox:, graph:|
        @notifier.instance_variable_set(:@mailbox, mailbox)
        @notifier
      end

      # Operator recipients: a user holding the finance permission.
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Admin::Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
    end

    teardown do
      NightlyBatchJob.store_builder = -> { Store.new }
      NightlyBatchJob.checker_builder = -> { ModulusCheck.default_checker }
      NightlyBatchJob.graph_builder = -> { GraphClient.new }
      NightlyBatchJob.notifier_builder = ->(mailbox:, graph:) { Notifier.new(mailbox: mailbox, graph: graph) }
    end

    def mailer_calls(name) = @notifier.calls.select { |call| call.first == name }

    # --- Branch 1: not a run-day ------------------------------------------

    test "skips a cost centre whose run-days don't include today" do
      # The previous run-day (Tue 07-07) is already recorded, so Wednesday has no
      # catch-up pending and the job is not due.
      CostCentre.default.update!(last_nightly_run_on: Date.new(2026, 7, 7))
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: WEDNESDAY)

      assert_empty @notifier.calls
      assert_equal Date.new(2026, 7, 7), CostCentre.default.reload.last_nightly_run_on
    end

    # --- Branch 2: stale-pending reminder ---------------------------------

    test "emails a pending reminder for submissions stuck awaiting approval" do
      stock_store([ pending_expense(days_ago: 5) ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      reminder = mailer_calls(:pending_reminder).sole.last
      assert_equal 1, reminder[:rows].size
      assert_equal 5, reminder[:rows].first[:age_days]
      # No approved work, so the run is still recorded (nothing else to do).
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "fresh pending submissions do not trigger a reminder" do
      stock_store([ pending_expense(days_ago: 1) ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_empty mailer_calls(:pending_reminder)
    end

    # --- Branch 3: needs-attention -> manual review and STOP --------------

    test "an AI-failed approved expense triggers manual review and no batch" do
      stock_store([ approved_expense(ai_status: "fail", **{ F[:ai_comment] => "amount mismatch" }) ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      review = mailer_calls(:manual_review).sole.last
      assert_equal 1, review[:issues].size
      assert_match(/amount mismatch/, review[:issues].first[:reason])
      assert_empty mailer_calls(:approved_ready), "no ready alert when an expense needs attention"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "an unchecked approved expense counts as an issue" do
      stock_store([ approved_expense(ai_status: "") ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      review = mailer_calls(:manual_review).sole.last
      assert_match(/not yet run/, review[:issues].first[:reason])
      assert_empty mailer_calls(:approved_ready)
    end

    # --- Branch 4: all clean -> ready-to-batch alert (nothing submitted) ---

    test "all-clean approved expenses email a ready-to-batch alert and submit nothing" do
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal 1, ready[:expenses].size
      assert_equal "12.50", ready[:total]
      assert_not ready.key?(:draft_link), "the nightly no longer builds a draft"
      assert_empty mailer_calls(:manual_review)
      assert_empty mailer_calls(:batch_ready), "no draft, so no draft-ready alert"
      # Nothing is submitted: the store sees no expense writes.
      assert_empty @client.updated, "the nightly must not submit or mutate expenses"
      # The alert is sent through a notifier built for the cost centre's send mailbox.
      assert_equal CostCentre.default.send_mailbox, @notifier.mailbox
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "builds the graph client once per run even when both the pending reminder and the " \
         "approved-ready alert fire" do
      stock_store([ pending_expense(days_ago: 5), approved_expense ])
      graph_builds = 0
      NightlyBatchJob.graph_builder = -> { graph_builds += 1; Object.new }

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal 1, mailer_calls(:pending_reminder).size
      assert_equal 1, mailer_calls(:approved_ready).size
      assert_equal 1, graph_builds,
                   "both notify calls in this run must share one GraphClient (one OAuth token fetch)"
    end

    test "a Graph email failure does not record the run, so the alert is retried, not lost" do
      @notifier = FakeNotifier.new(fail: true)
      stock_store([ approved_expense ])

      assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }

      # notify() swallows the Graph error internally, so run_for's outer rescue
      # never fires (no spurious failure email) — but the alert genuinely never
      # reached the operator, so the run must NOT be recorded: recording it here
      # would make nightly_due? treat this run-day as handled, silently losing
      # the alert forever instead of retrying it the next time the job runs.
      assert_empty mailer_calls(:failure)
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    test "a Graph credential failure escalates to the IT subcommittee, not an ordinary error email" do
      @notifier = FakeNotifier.new(fail: true, fail_with: Reimbursements::GraphAuth::AuthError)
      stock_store([ approved_expense ])

      assert_emails 1 do
        assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }
      end

      assert_match(/authentication is failing/, ActionMailer::Base.deliveries.last.subject)
      assert_empty mailer_calls(:failure), "an auth failure must not also trip the ordinary failure email"
      assert_nil CostCentre.default.reload.last_nightly_run_on
    ensure
      Rails.cache.delete(Reimbursements::GraphAuthAlert::CACHE_KEY)
    end

    test "an error raised mid-run emails failure and does not record the run (so it retries)" do
      NightlyBatchJob.store_builder = -> { BoomStore.new }

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal 1, mailer_calls(:failure).size
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    test "a DB failure recording the run after a successful alert doesn't trip a spurious failure email" do
      stock_store([ approved_expense ])
      original = CostCentre.instance_method(:record_nightly_run!)
      CostCentre.define_method(:record_nightly_run!) { |*| raise "DB blip" }

      notified = capture_honeybadger_notices { NightlyBatchJob.perform_now(today: THURSDAY) }

      # The approved-ready alert genuinely sent — the outer rescue must not
      # additionally fire and send a false "FAILED" email on top of that real
      # success just because the follow-up record write failed.
      assert_equal 1, mailer_calls(:approved_ready).size
      assert_empty mailer_calls(:failure)
      assert_equal 1, notified.size, "the record-write failure must still be reported"
    ensure
      CostCentre.define_method(:record_nightly_run!, original)
    end

    # --- Dry run -----------------------------------------------------------

    test "dry run logs decisions without sending email or recording" do
      stock_store([ approved_expense, pending_expense(days_ago: 5) ])

      NightlyBatchJob.perform_now(dry_run: true, today: THURSDAY)

      assert_empty @notifier.calls
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    # --- Operator recipients ----------------------------------------------

    test "operator emails go to the finance-permission holders" do
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_includes mailer_calls(:approved_ready).sole.last[:recipients], users(:member).email
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the recipient list" do
      ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = "shared-finance@bedlamfringe.co.uk"
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ "shared-finance@bedlamfringe.co.uk" ], mailer_calls(:approved_ready).sole.last[:recipients]
    ensure
      ENV.delete("REIMBURSEMENTS_OPERATOR_EMAIL")
    end

    test "with no operator recipients the run still records and doesn't crash" do
      # Strip the finance role set up above so operator_emails resolves to []
      # (and no ENV override), the same as a fresh install with nobody granted.
      Admin::Permission.where(action: "manage", subject_class: "reimbursements_finance").destroy_all
      stock_store([ approved_expense ])

      assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }

      assert_empty @notifier.calls, "no recipients -> the email send is skipped"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end
  end
end
