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

    class FakeProcessor
      Result = Struct.new(:success, :eusa_draft_web_link, :total_amount, :errors, keyword_init: true)
      attr_reader :calls

      def initialize(success: true, errors: [])
        @success = success
        @errors = errors
        @calls = []
      end

      def process(**kwargs)
        @calls << kwargs
        Result.new(success: @success, eusa_draft_web_link: "https://outlook.example/draft-1",
                   total_amount: kwargs[:expenses].sum { |e| e.amount || 0 }, errors: @errors)
      end
    end

    class FakeOperatorMailer
      Delivery = Struct.new(:noop) { def deliver_later = nil }
      class << self
        attr_accessor :calls

        def record(name, kwargs)
          (self.calls ||= []) << [ name, kwargs ]
          Delivery.new
        end

        def pending_reminder(**k) = record(:pending_reminder, k)
        def manual_review(**k) = record(:manual_review, k)
        def batch_ready(**k) = record(:batch_ready, k)
        def failure(**k) = record(:failure, k)
      end
    end

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
      @processor = FakeProcessor.new
      FakeOperatorMailer.calls = []
      NightlyBatchJob.checker_builder = -> { FakeChecker.new }
      NightlyBatchJob.processor_builder = ->(store:, graph:, cost_centre:) { @processor }
      NightlyBatchJob.graph_builder = -> { Object.new }
      NightlyBatchJob.mailer = FakeOperatorMailer

      # Operator recipients: a user holding the finance permission.
      finance = Role.create!(name: "Business Manager")
      finance.permissions << Admin::Permission.create(action: "manage", subject_class: "reimbursements_finance")
      users(:member).add_role("Business Manager")
    end

    teardown do
      NightlyBatchJob.store_builder = -> { Store.new }
      NightlyBatchJob.checker_builder = -> { ModulusCheck.default_checker }
      NightlyBatchJob.processor_builder =
        ->(store:, graph:, cost_centre:) { BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre) }
      NightlyBatchJob.graph_builder = -> { GraphClient.new }
      NightlyBatchJob.mailer = OperatorMailer
    end

    def mailer_calls(name) = FakeOperatorMailer.calls.select { |call| call.first == name }

    # --- Branch 1: not a run-day ------------------------------------------

    test "skips a cost centre whose run-days don't include today" do
      # The previous run-day (Tue 07-07) is already recorded, so Wednesday has no
      # catch-up pending and the job is not due.
      CostCentre.default.update!(last_nightly_run_on: Date.new(2026, 7, 7))
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: WEDNESDAY)

      assert_empty @processor.calls
      assert_empty FakeOperatorMailer.calls
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
      assert_empty @processor.calls, "must not build a batch when an expense needs attention"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "an unchecked approved expense counts as an issue" do
      stock_store([ approved_expense(ai_status: "") ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      review = mailer_calls(:manual_review).sole.last
      assert_match(/not yet run/, review[:issues].first[:reason])
      assert_empty @processor.calls
    end

    # --- Branch 4: all clean -> batch + operator email --------------------

    test "all-clean approved expenses run the batch and email the draft link" do
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal 1, @processor.calls.size
      ready = mailer_calls(:batch_ready).sole.last
      assert_equal "https://outlook.example/draft-1", ready[:draft_link]
      assert_empty mailer_calls(:manual_review)
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "a failed batch emails failure and does not record the run (so it retries)" do
      @processor = FakeProcessor.new(success: false, errors: [ "EUSA draft creation failed" ])
      NightlyBatchJob.processor_builder = ->(store:, graph:, cost_centre:) { @processor }
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal 1, mailer_calls(:failure).size
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    # --- Dry run -----------------------------------------------------------

    test "dry run logs decisions without sending email, batching, or recording" do
      stock_store([ approved_expense, pending_expense(days_ago: 5) ])

      NightlyBatchJob.perform_now(dry_run: true, today: THURSDAY)

      assert_empty @processor.calls
      assert_empty FakeOperatorMailer.calls
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    # --- Operator recipients ----------------------------------------------

    test "operator emails go to the finance-permission holders" do
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_includes mailer_calls(:batch_ready).sole.last[:recipients], users(:member).email
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the recipient list" do
      ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = "shared-finance@bedlamfringe.co.uk"
      stock_store([ approved_expense ])

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ "shared-finance@bedlamfringe.co.uk" ], mailer_calls(:batch_ready).sole.last[:recipients]
    ensure
      ENV.delete("REIMBURSEMENTS_OPERATOR_EMAIL")
    end

    test "with no operator recipients the batch still runs, records, and doesn't crash" do
      # Strip the finance role set up above so operator_emails resolves to []
      # (and no ENV override), the same as a fresh install with nobody granted.
      Admin::Permission.where(action: "manage", subject_class: "reimbursements_finance").destroy_all
      stock_store([ approved_expense ])

      assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }

      assert_equal 1, @processor.calls.size, "the batch is still submitted"
      assert_empty FakeOperatorMailer.calls, "no recipients -> the email send is skipped"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end
  end
end
