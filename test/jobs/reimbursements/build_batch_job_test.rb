require "test_helper"

module Reimbursements
  class BuildBatchJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    F = ReimbursementsTestHelpers::FIELD_IDS[:expenses]
    BACS_DATE = "2026-05-13".freeze
    OPERATOR = [ "operator@bedlamfringe.co.uk" ].freeze

    FakeProcessor = ReimbursementsTestHelpers::FakeBatchProcessor

    # Records the operator alerts sent through the Graph notifier plus the
    # mailbox it was built for. +fail+ makes every send raise (a Graph outage).
    class FakeNotifier
      attr_reader :calls, :mailbox

      def initialize(mailbox: nil, fail: false)
        @mailbox = mailbox
        @fail = fail
        @calls = []
      end

      def record(name, kwargs)
        raise Reimbursements::GraphAuth::Error, "graph down" if @fail

        @calls << [ name, kwargs ]
        nil
      end

      def batch_ready(**k) = record(:batch_ready, k)
      def failure(**k) = record(:failure, k)
    end

    def payee(**attrs)
      airtable_person_record(sort_code: "08-99-99", account_number: "66374958", **attrs)
    end

    def approved_expense(id: "recApp", **overrides)
      airtable_expense_record(id: id, status: "Approved", overrides: overrides)
    end

    def stock_store(expenses)
      @store, @client = build_fake_store(
        people: [ payee ], budgets: [ airtable_budget_record ], expenses: expenses
      )
      BuildBatchJob.store_builder = -> { @store }
    end

    def enqueue_args(**overrides)
      { cost_centre_key: CostCentre.default.key, bacs_date: BACS_DATE, sender_name: "Fringe Finance",
        eusa_recipient: "finance@eusa.ed.ac.uk", operator_emails: OPERATOR }.merge(overrides)
    end

    setup do
      @processor = FakeProcessor.new
      @notifier = FakeNotifier.new
      BuildBatchJob.processor_builder = ->(store:, graph:, cost_centre:) { @processor }
      BuildBatchJob.graph_builder = -> { Object.new }
      BuildBatchJob.notifier_builder = lambda do |mailbox:, graph:|
        @notifier.instance_variable_set(:@mailbox, mailbox)
        @notifier
      end
    end

    teardown do
      BuildBatchJob.store_builder = -> { Store.new }
      BuildBatchJob.processor_builder =
        ->(store:, graph:, cost_centre:) { BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre) }
      BuildBatchJob.graph_builder = -> { GraphClient.new }
      BuildBatchJob.notifier_builder = ->(mailbox:, graph:) { Notifier.new(mailbox: mailbox, graph: graph) }
    end

    def alerts(name) = @notifier.calls.select { |call| call.first == name }

    test "runs the batch on the approved expenses and emails the operator the draft link" do
      stock_store([ approved_expense ])

      BuildBatchJob.perform_now(**enqueue_args)

      assert_equal 1, @processor.calls.size
      call = @processor.calls.sole
      assert_equal Date.new(2026, 5, 13), call[:bacs_date], "the ISO string is parsed to a Date"
      assert_equal "finance@eusa.ed.ac.uk", call[:eusa_recipient]

      ready = alerts(:batch_ready).sole.last
      assert_equal OPERATOR, ready[:recipients]
      assert_equal "https://outlook.example/draft-1", ready[:draft_link]
      # The alert is sent from the cost centre's send mailbox.
      assert_equal CostCentre.default.send_mailbox, @notifier.mailbox
    end

    test "passes the operator's edited subject and body through to the processor" do
      stock_store([ approved_expense ])

      BuildBatchJob.perform_now(**enqueue_args(eusa_subject: "Custom subject", eusa_body_html: "<p>hi</p>"))

      call = @processor.calls.sole
      assert_equal "Custom subject", call[:eusa_subject]
      assert_equal "<p>hi</p>", call[:eusa_body_html]
    end

    test "no approved expenses: no-op, no processor call, no email (the serialised double-click case)" do
      # A serialised second build finds the expenses already Submitted.
      stock_store([ approved_expense(**{ F[:status] => "Submitted" }) ])

      BuildBatchJob.perform_now(**enqueue_args)

      assert_empty @processor.calls
      assert_empty @notifier.calls
    end

    test "a failed build emails the operator the failure with its errors" do
      @processor = FakeProcessor.new(success: false, errors: [ "EUSA draft creation failed" ])
      BuildBatchJob.processor_builder = ->(store:, graph:, cost_centre:) { @processor }
      stock_store([ approved_expense ])

      BuildBatchJob.perform_now(**enqueue_args)

      assert_empty alerts(:batch_ready)
      failure = alerts(:failure).sole.last
      assert_match(/EUSA draft creation failed/, failure[:error_text])
    end

    test "an unknown cost centre is a safe no-op" do
      stock_store([ approved_expense ])

      BuildBatchJob.perform_now(**enqueue_args(cost_centre_key: "nope"))

      assert_empty @processor.calls
      assert_empty @notifier.calls
    end

    test "with no operator recipients the batch still runs and the email is skipped" do
      stock_store([ approved_expense ])

      BuildBatchJob.perform_now(**enqueue_args(operator_emails: []))

      assert_equal 1, @processor.calls.size, "the batch is still submitted"
      assert_empty @notifier.calls, "no recipients -> the email send is skipped"
    end

    test "a Graph email outage doesn't fail the job (the batch already ran)" do
      @notifier = FakeNotifier.new(fail: true)
      stock_store([ approved_expense ])

      assert_nothing_raised { BuildBatchJob.perform_now(**enqueue_args) }

      assert_equal 1, @processor.calls.size
    end

    test "serialises builds per cost centre via the concurrency key" do
      job = BuildBatchJob.new(**enqueue_args(cost_centre_key: "fringe"))

      assert_equal "Reimbursements::BuildBatchJob/reimbursements_build_batch_fringe", job.concurrency_key
    end
  end
end
