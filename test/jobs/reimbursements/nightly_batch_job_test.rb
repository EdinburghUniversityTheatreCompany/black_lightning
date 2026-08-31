require "test_helper"

module Reimbursements
  class NightlyBatchJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    MC = ModulusCheck

    # 2026-07-09 is a Thursday (wday 4); fringe's default run-days are [2, 4],
    # so the nightly is due. 2026-07-08 is a Wednesday (not a run-day).
    THURSDAY = Date.new(2026, 7, 9)
    WEDNESDAY = Date.new(2026, 7, 8)

    class FakeChecker
      def check(_sort, _account) = MC::VALID
    end

    # A store whose expenses read raises, standing in for a data-layer outage —
    # drives the nightly's top-level rescue (handle_failure).
    class BoomStore
      def expenses = raise(StandardError, "backend down")
    end

    FakeNotifier = ReimbursementsTestHelpers::FakeNotifier

    def payee
      @payee ||= create_reimbursements_person(sort_code: "08-99-99", account_number: "66374958")
    end

    def budget
      @budget ||= create_reimbursements_budget
    end

    def approved_expense(**attrs)
      create_reimbursements_expense(person: payee, budget: budget, status: Status::APPROVED, **attrs)
    end

    def pending_expense(days_ago: 5)
      create_reimbursements_expense(person: payee, budget: budget, status: Status::PENDING,
                                    submitted_at: THURSDAY.to_time(:utc) - days_ago.days)
    end

    setup do
      @notifier = FakeNotifier.new
      NightlyBatchJob.checker_builder = -> { FakeChecker.new }
      NightlyBatchJob.graph_builder = -> { Object.new }
      # Capture the mailbox the notifier is built for so a test can assert the
      # operator alerts send from the cost centre's send mailbox.
      NightlyBatchJob.notifier_builder = lambda do |cost_centre:, graph:|
        @notifier.instance_variable_set(:@mailbox, cost_centre.send_mailbox)
        @notifier
      end

      # Operator recipients come from the cost centre's notification role, not
      # from the finance permission grid. The fixture role is empty on purpose,
      # so every test that expects mail to go out says so here.
      roles(:fringe_finance_admin).users << users(:member)
    end

    teardown do
      NightlyBatchJob.store_builder = -> { Reimbursements.build_store }
      NightlyBatchJob.checker_builder = -> { ModulusCheck.default_checker }
      NightlyBatchJob.graph_builder = -> { GraphClient.new }
      NightlyBatchJob.notifier_builder =
        ->(cost_centre:, graph:) { Notifier.new(cost_centre: cost_centre, graph: graph) }
    end

    def mailer_calls(name) = @notifier.calls.select { |call| call.first == name }

    # --- Branch 1: not a run-day ------------------------------------------

    test "skips a cost centre whose run-days don't include today" do
      # The previous run-day (Tue 07-07) is already recorded, so Wednesday has no
      # catch-up pending and the job is not due.
      CostCentre.default.update!(last_nightly_run_on: Date.new(2026, 7, 7))
      approved_expense

      NightlyBatchJob.perform_now(today: WEDNESDAY)

      assert_empty @notifier.calls
      assert_equal Date.new(2026, 7, 7), CostCentre.default.reload.last_nightly_run_on
    end

    # --- Branch 2: stale-pending reminder ---------------------------------

    test "emails a pending reminder for submissions stuck awaiting approval" do
      pending_expense(days_ago: 5)

      NightlyBatchJob.perform_now(today: THURSDAY)

      reminder = mailer_calls(:pending_reminder).sole.last
      assert_equal 1, reminder[:rows].size
      assert_equal 5, reminder[:rows].first[:age_days]
      # The approved reminder had nothing to say, which counts as delivered, so
      # the run is recorded.
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "fresh pending submissions do not trigger a reminder" do
      pending_expense(days_ago: 1)

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_empty mailer_calls(:pending_reminder)
    end

    # --- Branch 3: needs-attention is flagged, never held back ------------

    test "an approved expense needing attention is still listed, flagged rather than held back" do
      # No receipt: ReviewSupport.needs_attention_reasons flags it. The nightly
      # is a reminder, not a gate, so the claim must still reach the operator's
      # list (and its amount must still count towards the total) — the old
      # behaviour replaced the whole list with a "manual review" email.
      approved_expense(receipt: false)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal 1, ready[:expenses].size
      assert_includes ready[:expenses].sole[:flags].join("; "), "receipt"
      assert_equal "12.50", ready[:total], "a flagged claim still counts towards the total"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "clean and flagged approved expenses arrive in one alert, clean first" do
      approved_expense
      approved_expense(receipt: false)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal 2, ready[:expenses].size, "one alert covers the whole Approved queue"
      assert_empty ready[:expenses].first[:flags]
      assert_not_empty ready[:expenses].last[:flags], "flagged claims sort to the bottom"
    end

    # --- Branch 4: all clean -> ready-to-batch alert (nothing submitted) ---

    test "all-clean approved expenses email a ready-to-batch alert and submit nothing" do
      expense = approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal 1, ready[:expenses].size
      assert_equal "12.50", ready[:total]
      assert_not ready.key?(:draft_link), "the nightly no longer builds a draft"
      assert_empty ready[:expenses].sole[:flags], "a clean claim carries no flags"
      # Pinned at the caller, not just in notifier_test: the Notifier renders
      # next_run_day only when it is passed one, so dropping the kwarg here
      # would silently lose "the next reminder is …" with every test green.
      assert_equal "Tuesday 14 July", ready[:next_run_day]
      assert_empty mailer_calls(:batch_ready), "no draft, so no draft-ready alert"
      # Nothing is submitted: the nightly must not mutate expenses.
      assert_equal Status::APPROVED, expense.reload.status
      # The alert is sent through a notifier built for the cost centre's send mailbox.
      assert_equal CostCentre.default.send_mailbox, @notifier.mailbox
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "a second cost centre with none of its own claims emails nothing and still records its run" do
      # What survives of the old cost-centre-unscoped guard: a due centre with an
      # empty queue must not re-remind on another centre's claims, and a reminder
      # with nothing to say still counts as delivered, so its run-day is recorded.
      second = create_reimbursements_cost_centre(key: "extra", name: "Second Society", eusa_code: "X99",
                                                 receive_mailbox: "in@second.co.uk",
                                                 send_mailbox: "send@second.co.uk",
                                                 notification_users: [ users(:committee) ])
      assert_not_equal CostCentre.default, second
      approved_expense
      pending_expense(days_ago: 5)

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ [ users(:member).email ] ], mailer_calls(:approved_ready).map { |(_, k)| k[:recipients] },
                   "the claims belong to the default centre, so only its recipients hear about them"
      assert_equal [ [ users(:member).email ] ], mailer_calls(:pending_reminder).map { |(_, k)| k[:recipients] }
      assert_equal THURSDAY, second.reload.last_nightly_run_on,
                   "the second cost centre still records its own nightly run"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on,
                   "and the default centre — the one that actually sent — records its own"
    end

    test "builds the graph client once per run even when both the pending reminder and the " \
         "approved-ready alert fire" do
      pending_expense(days_ago: 5)
      approved_expense
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
      approved_expense

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
      @notifier = FakeNotifier.new(fail: true, fail_with: ::GraphAuth::AuthError)
      approved_expense

      assert_emails 1 do
        assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }
      end

      assert_match(/authentication is failing/, ActionMailer::Base.deliveries.last.subject)
      assert_empty mailer_calls(:failure), "an auth failure must not also trip the ordinary failure email"
      assert_nil CostCentre.default.reload.last_nightly_run_on
    ensure
      Rails.cache.delete(Reimbursements::GraphAuthAlert::CACHE_KEY)
    end

    # Both reminders send independently, so a run can half-succeed. Recording the
    # run-day marks it handled forever (nightly_due? then skips it) and there is
    # no retry queue behind these alerts, so ANY failed send must block the
    # record — at the cost of re-sending the one that worked tomorrow.
    test "a failed pending reminder blocks recording the run, even though the approved alert sent" do
      @notifier = FakeNotifier.new(fail_only: [ :pending_reminder ])
      pending_expense(days_ago: 5)
      approved_expense

      assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }

      assert_equal 1, mailer_calls(:approved_ready).size,
                   "the approved reminder must still be ATTEMPTED after the pending one fails"
      assert_empty mailer_calls(:pending_reminder)
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    test "a failed approved reminder blocks recording the run, even though the pending one sent" do
      @notifier = FakeNotifier.new(fail_only: [ :approved_ready ])
      pending_expense(days_ago: 5)
      approved_expense

      assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }

      assert_equal 1, mailer_calls(:pending_reminder).size
      assert_empty mailer_calls(:approved_ready)
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    test "a quiet run sends nothing and still records the run-day" do
      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_empty @notifier.calls, "no pending and no approved work means no email at all"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on,
                   "a reminder with nothing to say counts as delivered"
    end

    test "an error raised mid-run emails failure and does not record the run (so it retries)" do
      NightlyBatchJob.store_builder = -> { BoomStore.new }

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal 1, mailer_calls(:failure).size
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    test "a preview run never sends a real failure email, even when the run itself raises" do
      NightlyBatchJob.store_builder = -> { BoomStore.new }

      assert_nothing_raised { NightlyBatchJob.perform_now(dry_run: true, today: THURSDAY) }

      assert_empty mailer_calls(:failure), "dry_run must still log-and-notify Honeybadger, but never email"
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    test "a DB failure recording the run after a successful alert doesn't trip a spurious failure email" do
      approved_expense
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
      approved_expense
      pending_expense(days_ago: 5)

      NightlyBatchJob.perform_now(dry_run: true, today: THURSDAY)

      assert_empty @notifier.calls
      assert_nil CostCentre.default.reload.last_nightly_run_on
    end

    # --- Operator recipients ----------------------------------------------

    test "operator emails go to the cost centre's notification role" do
      approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_includes mailer_calls(:approved_ready).sole.last[:recipients], users(:member).email
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the recipient list" do
      ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = "shared-finance@bedlamfringe.co.uk"
      approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ "shared-finance@bedlamfringe.co.uk" ], mailer_calls(:approved_ready).sole.last[:recipients]
    ensure
      ENV.delete("REIMBURSEMENTS_OPERATOR_EMAIL")
    end

    test "an empty notification role sends nothing and does not record the run" do
      # The old behaviour counted "nobody to email" as delivered, which recorded
      # the run-day and lost the alert forever. Leaving it unrecorded means
      # tomorrow's run tries again and keeps alarming until the role is filled.
      roles(:fringe_finance_admin).users.clear
      approved_expense

      events = capture_honeybadger_events do
        assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }
      end

      assert_empty @notifier.calls, "no recipients -> nothing is even built"
      assert_nil CostCentre.default.reload.last_nightly_run_on
      assert_includes events.map(&:first), "reimbursements.nightly_no_recipients"
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL still overrides an empty notification role" do
      # The divert-everything switch must reach the send, not be cut off by the
      # empty-role guard in front of it.
      roles(:fringe_finance_admin).users.clear
      ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = "ops@example.com"
      approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ "ops@example.com" ], mailer_calls(:approved_ready).sole.last[:recipients]
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    ensure
      ENV.delete("REIMBURSEMENTS_OPERATOR_EMAIL")
    end

    # --- Per-cost-centre scoping ------------------------------------------

    test "each due cost centre is reminded about only its own claims" do
      termtime = create_reimbursements_cost_centre(
        key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "in@termtime.co.uk", send_mailbox: "send@termtime.co.uk",
        notification_users: [ users(:committee) ], nightly_run_days: [ 4 ]
      )
      termtime_budget = create_reimbursements_budget(name: "Termtime props")
      termtime_budget.update!(cost_centre: termtime)
      budget.update!(cost_centre: CostCentre.default)

      fringe_claim = approved_expense
      termtime_claim = create_reimbursements_expense(person: payee, budget: termtime_budget,
                                                     status: Status::APPROVED)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready)
      assert_equal 2, ready.size

      by_recipient = ready.to_h { |(_name, kwargs)| [ kwargs[:recipients].sort, kwargs[:expenses] ] }
      fringe_rows = by_recipient.fetch([ users(:member).email ])
      termtime_rows = by_recipient.fetch([ users(:committee).email ])

      assert_equal [ fringe_claim.auto_number ], fringe_rows.map { |row| row[:auto_number] }
      assert_equal [ termtime_claim.auto_number ], termtime_rows.map { |row| row[:auto_number] }
    end

    test "a claim whose budget has no cost centre falls to the default centre" do
      budget.update!(cost_centre: nil)
      approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal [ users(:member).email ], ready[:recipients]
      assert_equal 1, ready[:expenses].size
    end

    test "a non-default cost centre reports on its own run-day" do
      termtime = create_reimbursements_cost_centre(
        key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "in@termtime.co.uk", send_mailbox: "send@termtime.co.uk",
        notification_users: [ users(:committee) ], nightly_run_days: [ 4 ]
      )
      # The default centre is NOT due today, so the old skip_unscoped_cost_centre
      # guard would have silenced termtime entirely.
      CostCentre.default.update!(nightly_run_days: [ 1 ], last_nightly_run_on: THURSDAY - 1)
      termtime_budget = create_reimbursements_budget(name: "Termtime props")
      termtime_budget.update!(cost_centre: termtime)
      create_reimbursements_expense(person: payee, budget: termtime_budget, status: Status::APPROVED)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal [ users(:committee).email ], ready[:recipients]
      assert_equal THURSDAY, termtime.reload.last_nightly_run_on
    end
  end
end
