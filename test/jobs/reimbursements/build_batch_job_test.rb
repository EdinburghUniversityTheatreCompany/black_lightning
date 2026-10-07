require "test_helper"

module Reimbursements
  class BuildBatchJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    BACS_DATE = "2026-05-13".freeze
    OPERATOR = [ "operator@bedlamfringe.co.uk" ].freeze

    def payee
      @payee ||= create_reimbursements_person(sort_code: "08-99-99", account_number: "66374958")
    end

    def approved_expense(status: Status::APPROVED)
      create_reimbursements_expense(person: payee, budget: create_reimbursements_budget,
                                    status: status)
    end

    def enqueue_args(**overrides)
      { cost_centre_key: CostCentre.default.key, bacs_date: BACS_DATE, sender_name: "Fringe Finance",
        eusa_recipient: "finance@eusa.ed.ac.uk", operator_emails: OPERATOR }.merge(overrides)
    end

    def click_time_attempt
      BatchAttempt.create!(cost_centre: CostCentre.default, bacs_date: Date.new(2026, 5, 13),
                           triggered_by_email: OPERATOR.first)
    end

    setup do
      @processor = FakeBatchProcessor.new
      @notifier = FakeNotifier.new
      BuildBatchJob.processor_builder = ->(store:, graph:, cost_centre:) { @processor }
      BuildBatchJob.graph_builder = -> { Object.new }
      BuildBatchJob.notifier_builder = lambda do |cost_centre:, graph:|
        @notifier.instance_variable_set(:@mailbox, cost_centre.send_mailbox)
        @notifier
      end
    end

    teardown do
      BuildBatchJob.processor_builder =
        ->(store:, graph:, cost_centre:) { BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre) }
      BuildBatchJob.graph_builder = -> { GraphClient.new }
      BuildBatchJob.notifier_builder =
        ->(cost_centre:, graph:) { Notifier.new(cost_centre: cost_centre, graph: graph) }
    end

    def alerts(name) = @notifier.calls.select { |call| call.first == name }

    test "runs the batch on the approved expenses and emails the operator the draft link" do
      approved_expense

      BuildBatchJob.perform_now(**enqueue_args)

      call = @processor.calls.sole
      assert_equal Date.new(2026, 5, 13), call[:bacs_date], "the ISO string is parsed to a Date"
      assert_equal "finance@eusa.ed.ac.uk", call[:eusa_recipient]

      ready = alerts(:batch_ready).sole.last
      assert_equal OPERATOR, ready[:recipients]
      assert_equal "https://outlook.example/draft-1", ready[:draft_link]
      assert_equal CostCentre.default.send_mailbox, @notifier.mailbox

      attempt = BatchAttempt.sole
      assert attempt.completed?
      assert_equal OPERATOR.first, attempt.triggered_by_email
    end

    test "a malformed bacs_date falls back to today rather than raising" do
      approved_expense

      travel_to Time.zone.local(2026, 5, 20) do
        BuildBatchJob.perform_now(**enqueue_args(bacs_date: "not-a-date"))
      end

      assert_equal Date.new(2026, 5, 20), @processor.calls.sole[:bacs_date]
    end

    test "builds the graph client once per run, not once per call site" do
      approved_expense
      graph_builds = 0
      BuildBatchJob.graph_builder = -> { graph_builds += 1; Object.new }

      BuildBatchJob.perform_now(**enqueue_args)

      assert_equal 1, graph_builds,
                   "the processor and the notifier must share one GraphClient (one OAuth token fetch), not one each"
    end

    test "passes the operator's edited subject and body through to the processor" do
      approved_expense

      BuildBatchJob.perform_now(**enqueue_args(eusa_subject: "Custom subject", eusa_body_html: "<p>hi</p>"))

      call = @processor.calls.sole
      assert_equal "Custom subject", call[:eusa_subject]
      assert_equal "<p>hi</p>", call[:eusa_body_html]
    end

    # The preview is only a preview: the job re-selects the Approved set at run
    # time, so the narrowing to one centre has to be here too.
    test "builds only its own centre's claims" do
      termtime = create_second_reimbursements_cost_centre
      create_reimbursements_expense(person: payee, budget: create_reimbursements_budget(cost_centre: CostCentre.default),
                                    status: Status::APPROVED, auto_number: 11)
      create_reimbursements_expense(person: payee,
                                    budget: create_reimbursements_budget(name: "Termtime props", cost_centre: termtime),
                                    status: Status::APPROVED, auto_number: 12)

      BuildBatchJob.perform_now(**enqueue_args(cost_centre_key: "termtime"))

      assert_equal [ 12 ], @processor.calls.sole[:expenses].map(&:auto_number)
    end

    test "no approved expenses: no-op, no processor call, no email (the serialised double-click case)" do
      # A serialised second build finds the expenses already Submitted.
      approved_expense(status: Status::SUBMITTED)
      attempt = click_time_attempt

      BuildBatchJob.perform_now(**enqueue_args(attempt_id: attempt.id))

      assert_empty @processor.calls
      assert_empty @notifier.calls
      assert attempt.reload.nothing_to_build?
    end

    test "a failed build emails the operator the failure and fails its attempt with the errors" do
      @processor = FakeBatchProcessor.new(success: false, errors: [ "EUSA draft creation failed" ])
      attempt = click_time_attempt
      approved_expense

      BuildBatchJob.perform_now(**enqueue_args(attempt_id: attempt.id))

      assert_empty alerts(:batch_ready)
      failure = alerts(:failure).sole.last
      assert_match(/EUSA draft creation failed/, failure[:error_text])
      assert attempt.reload.failed?
      assert_includes attempt.error_messages, "EUSA draft creation failed"
    end

    test "a Graph credential failure notifying the operator escalates to IT, not a doomed retry" do
      @notifier = FakeNotifier.new(fail: true, fail_with: ::GraphAuth::AuthError)
      approved_expense

      assert_emails 1 do
        assert_nothing_raised { BuildBatchJob.perform_now(**enqueue_args) }
      end

      assert_match(/authentication is failing/, ActionMailer::Base.deliveries.last.subject)
    ensure
      Rails.cache.delete(Reimbursements::GraphAuthAlert::CACHE_KEY)
    end

    test "a Graph credential failure inside the batch build itself escalates to IT and fails the attempt" do
      @processor.define_singleton_method(:process) { |**| raise ::GraphAuth::AuthError, "token expired" }
      attempt = click_time_attempt
      approved_expense

      assert_emails 1 do
        assert_nothing_raised { BuildBatchJob.perform_now(**enqueue_args(attempt_id: attempt.id)) }
      end

      assert_match(/authentication is failing/, ActionMailer::Base.deliveries.last.subject)
      assert_empty @notifier.calls, "no operator email is attempted once Graph auth itself is broken"
      assert attempt.reload.failed?
      assert_includes attempt.error_messages, "token expired"
    ensure
      Rails.cache.delete(Reimbursements::GraphAuthAlert::CACHE_KEY)
    end

    # --- BatchAttempt lifecycle: History's in-app trace of each build ------

    test "a successful build with best-effort failures keeps them as warnings on the attempt" do
      @processor = FakeBatchProcessor.new(success: true, errors: [ "BACS file SharePoint upload failed" ])
      attempt = click_time_attempt
      approved_expense

      BuildBatchJob.perform_now(**enqueue_args(attempt_id: attempt.id))

      assert attempt.reload.completed?
      assert_includes attempt.error_messages, "SharePoint upload failed"
    end

    test "resolves exactly its own attempt by id, never a leftover building row from a prior build" do
      # A prior build died leaving r_old 'building'.
      r_old = click_time_attempt
      r_mine = click_time_attempt
      approved_expense

      BuildBatchJob.perform_now(**enqueue_args(attempt_id: r_mine.id))

      assert r_mine.reload.completed?, "my row is resolved"
      assert_equal "recBat1", r_mine.batch_record_id
      assert_nil r_mine.error_messages, "a clean build stores no warnings"
      assert r_old.reload.building?, "the leftover row is untouched, not mislabelled with my result"
    end

    test "a cost centre gone between click and run is a no-op that fails its attempt, not left building" do
      approved_expense
      attempt = click_time_attempt

      BuildBatchJob.perform_now(**enqueue_args(cost_centre_key: "gone", attempt_id: attempt.id))

      assert_empty @processor.calls
      assert_empty @notifier.calls
      assert attempt.reload.failed?, "the row must not linger in 'building' forever"
      assert_includes attempt.error_messages, "no longer exists"
    end

    test "with no operator recipients the batch still runs and the email is skipped" do
      approved_expense

      BuildBatchJob.perform_now(**enqueue_args(operator_emails: []))

      assert_equal 1, @processor.calls.size, "the batch is still submitted"
      assert_empty @notifier.calls, "no recipients -> the email send is skipped"
    end

    test "a Graph email outage doesn't fail the job (the batch already ran)" do
      @notifier = FakeNotifier.new(fail: true)
      approved_expense

      assert_nothing_raised { BuildBatchJob.perform_now(**enqueue_args) }

      assert_equal 1, @processor.calls.size
    end

    test "serialises builds per cost centre via the concurrency key" do
      job = BuildBatchJob.new(**enqueue_args(cost_centre_key: "fringe"))

      assert_equal "Reimbursements::BuildBatchJob/reimbursements_build_batch_fringe", job.concurrency_key
    end
  end
end
