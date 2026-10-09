require "test_helper"

module Reimbursements
  class NightlyBatchJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # The fixture centre's run-days are Tuesday and Thursday.
    THURSDAY = Date.new(2026, 7, 9)
    WEDNESDAY = Date.new(2026, 7, 8)

    # The fixture centre's notification_email, and one for second centres.
    FRINGE_EMAIL = "finance@bedlamfringe.invalid".freeze
    SECOND_EMAIL = "finance@second.invalid".freeze

    # A data-layer outage, driving the job's top-level rescue.
    class BoomStore
      def expenses_owned_by_cost_centre(_centre) = raise(StandardError, "backend down")
    end

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

    # An owner who is not the submitter, so the claim awaits their sign-off.
    def owner_person
      @owner_person ||= create_reimbursements_person(name: "Olive Owner",
                                                     email: "olive@example.com")
    end

    def owned_budget
      @owned_budget ||= create_reimbursements_budget(name: "Owned Set", nominal_code: "4100",
                                                     owners: [ owner_person ])
    end

    def gated_pending(days_ago: 5)
      create_reimbursements_expense(person: payee, budget: owned_budget, status: Status::PENDING,
                                    submitted_at: THURSDAY.to_time(:utc) - days_ago.days)
    end

    setup do
      @notifier = FakeNotifier.new
      NightlyBatchJob.checker_builder = -> { FakeModulusChecker.new("66374958" => ModulusCheck::VALID) }
      NightlyBatchJob.graph_builder = -> { Object.new }
      # Records the mailbox the notifier is built for.
      NightlyBatchJob.notifier_builder = lambda do |cost_centre:, graph:|
        @notifier.instance_variable_set(:@mailbox, cost_centre.send_mailbox)
        @notifier
      end
    end

    teardown do
      NightlyBatchJob.store_builder = -> { Reimbursements.build_store }
      NightlyBatchJob.checker_builder = -> { ModulusCheck.default_checker }
      NightlyBatchJob.graph_builder = -> { GraphClient.new }
      NightlyBatchJob.notifier_builder =
        ->(cost_centre:, graph:) { Notifier.new(cost_centre: cost_centre, graph: graph) }
    end

    def mailer_calls(name) = @notifier.calls.select { |call| call.first == name }

    # --- Not a run-day ----------------------------------------------------

    test "skips a cost centre whose run-days don't include today" do
      # Tuesday is recorded, so Wednesday has no catch-up due.
      CostCentre.default.update!(last_nightly_run_on: Date.new(2026, 7, 7))
      approved_expense

      NightlyBatchJob.perform_now(today: WEDNESDAY)

      assert_empty @notifier.calls
      assert_equal Date.new(2026, 7, 7), CostCentre.default.reload.last_nightly_run_on
    end

    # --- Stale-pending reminder -------------------------------------------

    test "emails a pending reminder for submissions stuck awaiting approval" do
      expense = pending_expense(days_ago: 5)

      NightlyBatchJob.perform_now(today: THURSDAY)

      row = mailer_calls(:pending_reminder).sole.last[:rows].sole
      assert_equal 5, row[:age_days]
      assert_equal expense.record_id, row[:record_id], "the claim's id builds its edit link"
      assert_empty mailer_calls(:owner_sign_off_reminder), "an ownerless budget's claim stays finance's"
      # Nothing approved counts as delivered.
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "fresh pending submissions do not trigger a reminder" do
      pending_expense(days_ago: 1)

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_empty mailer_calls(:pending_reminder)
    end

    # --- Owner sign-off reminder ------------------------------------------
    # A claim awaiting a budget owner goes to the owner, not to finance.

    test "emails each budget owner one reminder listing every claim awaiting their sign-off" do
      first = gated_pending(days_ago: 5)
      second = gated_pending(days_ago: 2)

      NightlyBatchJob.perform_now(today: THURSDAY)

      reminder = mailer_calls(:owner_sign_off_reminder).sole.last
      assert_equal [ owner_person.email ], reminder[:to]
      assert_equal "Olive", reminder[:greeting_name]
      assert_equal [ first.auto_number, second.auto_number ].sort,
                   reminder[:rows].map { |row| row[:auto_number] }.sort
      assert_equal owned_budget.name, reminder[:rows].first[:budget_name]
      assert_empty mailer_calls(:pending_reminder), "finance is not reminded about a claim that is not theirs yet"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    # An owner of two shows must be told which show's "Marketing" a claim is on.
    test "the owner reminder names the show, not just the category" do
      # The owner goes on the AREA: Budget#owners reads through it.
      area = create_reimbursements_area(name: "Cogito")
      area.owners << owner_person
      owned_budget.update!(area: area)
      gated_pending(days_ago: 5)

      NightlyBatchJob.perform_now(today: THURSDAY)

      reminder = mailer_calls(:owner_sign_off_reminder).sole.last
      assert_equal "Cogito: Owned Set", reminder[:rows].sole[:budget_name]
    end

    test "a claim awaiting sign-off is reminded with no age threshold" do
      gated_pending(days_ago: 0)

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal 1, mailer_calls(:owner_sign_off_reminder).size
    end

    test "an endorsed claim reminds nobody" do
      claim = gated_pending(days_ago: 5)
      OwnerEndorsement.create!(expense_record_id: claim.record_id,
                               budget_record_id: owned_budget.record_id,
                               endorsed_by_person_id: owner_person.record_id,
                               endorsed_amount: claim.amount, endorsed_at: Time.current)

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_empty mailer_calls(:owner_sign_off_reminder)
      # Finance's now, and stale.
      assert_equal 1, mailer_calls(:pending_reminder).size
    end

    test "each owner is told who else owns the budget, and nobody is told about themselves" do
      ann = create_reimbursements_person(name: "Ann Other", email: "ann@example.com")
      owned_budget.own_owners << ann
      gated_pending

      NightlyBatchJob.perform_now(today: THURSDAY)

      rows = mailer_calls(:owner_sign_off_reminder).to_h { |_, call| [ call[:to].sole, call[:rows].sole ] }
      assert_equal "Ann Other", rows["olive@example.com"][:also_owned_by]
      assert_equal "Olive Owner", rows["ann@example.com"][:also_owned_by]
    end

    test "owner rows carry the budget id and skip a co-owner with no name" do
      blank = create_reimbursements_person(name: "Temp", email: "blank@example.com")
      blank.update_columns(name: "")
      owned_budget.own_owners << blank
      owned_budget.own_owners << create_reimbursements_person(name: "Bo Other", email: "bo@example.com")
      gated_pending

      NightlyBatchJob.perform_now(today: THURSDAY)

      row = mailer_calls(:owner_sign_off_reminder).find { |_, call| call[:to] == [ owner_person.email ] }.last[:rows].sole
      assert_equal owned_budget.record_id, row[:budget_id]
      assert_equal "Bo Other", row[:also_owned_by]
    end

    test "an owner with no email address is skipped rather than raising" do
      owner_person.update!(email: nil)
      gated_pending(days_ago: 5)

      assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }

      assert_empty mailer_calls(:owner_sign_off_reminder)
      # Nothing failed either, so the run still records.
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "a failed owner reminder is best effort and still records the run-day" do
      # An owner's dead address must not withhold the run-day and re-send
      # finance's reminders tomorrow.
      @notifier = FakeNotifier.new(fail_only: [ :owner_sign_off_reminder ])
      gated_pending(days_ago: 5)
      pending_expense(days_ago: 5)

      events = capture_honeybadger_events { NightlyBatchJob.perform_now(today: THURSDAY) }

      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
      assert_includes events.map(&:first), "reimbursements.owner_reminder_failed"
      assert_equal 1, mailer_calls(:pending_reminder).size
    end

    # --- Approved reminder ------------------------------------------------

    test "clean and flagged approved expenses arrive in one alert, clean first" do
      approved_expense
      # No receipt, so it is flagged. A reminder, not a gate: still listed.
      approved_expense(receipt: false)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal 2, ready[:expenses].size, "one alert covers the whole Approved queue"
      assert_empty ready[:expenses].first[:flags]
      assert_not_empty ready[:expenses].last[:flags], "flagged claims sort to the bottom"
      assert_includes ready[:expenses].last[:flags].join("; "), "receipt"
      assert_equal "25.00", ready[:total], "a flagged claim still counts towards the total"
    end

    test "all-clean approved expenses email a ready-to-batch alert and submit nothing" do
      expense = approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal 1, ready[:expenses].size
      assert_equal "12.50", ready[:total]
      assert_not ready.key?(:draft_link), "the nightly no longer builds a draft"
      assert_empty ready[:expenses].sole[:flags], "a clean claim carries no flags"
      # Pinned here: the Notifier renders next_run_day only when it is passed one.
      assert_equal "Tuesday 14 July", ready[:next_run_day]
      assert_empty mailer_calls(:batch_ready), "no draft, so no draft-ready alert"
      assert_equal Status::APPROVED, expense.reload.status
      assert_equal CostCentre.default.send_mailbox, @notifier.mailbox
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on
    end

    test "a second cost centre with none of its own claims emails nothing and still records its run" do
      # A due centre with an empty queue reminds nobody about another centre's
      # claims, and still records its run-day.
      second = create_second_reimbursements_cost_centre(notification_email: SECOND_EMAIL)
      approved_expense
      pending_expense(days_ago: 5)

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ [ FRINGE_EMAIL ] ], mailer_calls(:approved_ready).map { |(_, k)| k[:recipients] },
                   "the claims belong to the default centre, so only its recipients hear about them"
      assert_equal [ [ FRINGE_EMAIL ] ], mailer_calls(:pending_reminder).map { |(_, k)| k[:recipients] }
      assert_equal THURSDAY, second.reload.last_nightly_run_on,
                   "the second cost centre still records its own nightly run"
      assert_equal THURSDAY, CostCentre.default.reload.last_nightly_run_on,
                   "and the default centre: the one that actually sent: records its own"
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

    test "a Graph credential failure escalates to the IT subcommittee, not an ordinary error email" do
      @notifier = FakeNotifier.new(fail_only: [ :approved_ready ], fail_with: ::GraphAuth::AuthError)
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

    # Recording the run-day marks it handled forever, so ANY failed send blocks it.
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
      assert_empty mailer_calls(:failure), "a failed send is swallowed, not a run failure"
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

      # The alert sent, so a failed record write must not add a FAILED email.
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

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the recipient list" do
      ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = "shared-finance@bedlamfringe.co.uk"
      approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      assert_equal [ "shared-finance@bedlamfringe.co.uk" ], mailer_calls(:approved_ready).sole.last[:recipients]
    ensure
      ENV.delete("REIMBURSEMENTS_OPERATOR_EMAIL")
    end

    test "no notification address sends nothing and does not record the run" do
      # update_columns because presence is validated on the model.
      CostCentre.default.update_columns(notification_email: nil)
      approved_expense

      events = capture_honeybadger_events do
        assert_nothing_raised { NightlyBatchJob.perform_now(today: THURSDAY) }
      end

      assert_empty @notifier.calls, "no recipients -> nothing is even built"
      assert_nil CostCentre.default.reload.last_nightly_run_on
      assert_includes events.map(&:first), "reimbursements.nightly_no_recipients"
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL still overrides a missing address" do
      # The override must not be cut off by the no-recipients guard.
      CostCentre.default.update_columns(notification_email: nil)
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
      termtime = create_second_reimbursements_cost_centre(notification_email: SECOND_EMAIL,
                                                          nightly_run_days: [ 4 ])
      termtime_budget = create_reimbursements_budget(name: "Termtime props", cost_centre: termtime)
      budget.update!(cost_centre: CostCentre.default)

      fringe_claim = approved_expense
      termtime_claim = create_reimbursements_expense(person: payee, budget: termtime_budget,
                                                     status: Status::APPROVED)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready)
      assert_equal 2, ready.size

      by_recipient = ready.to_h { |(_name, kwargs)| [ kwargs[:recipients].sort, kwargs[:expenses] ] }
      fringe_rows = by_recipient.fetch([ FRINGE_EMAIL ])
      termtime_rows = by_recipient.fetch([ SECOND_EMAIL ])

      assert_equal [ fringe_claim.auto_number ], fringe_rows.map { |row| row[:auto_number] }
      assert_equal [ termtime_claim.auto_number ], termtime_rows.map { |row| row[:auto_number] }
    end

    test "a claim whose budget has no cost centre falls to the default centre" do
      budget.update!(cost_centre: nil)
      approved_expense

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal [ FRINGE_EMAIL ], ready[:recipients]
      assert_equal 1, ready[:expenses].size
    end

    test "a non-default cost centre reports on its own run-day" do
      termtime = create_second_reimbursements_cost_centre(notification_email: SECOND_EMAIL,
                                                          nightly_run_days: [ 4 ])
      # The default centre is not due today.
      CostCentre.default.update!(nightly_run_days: [ 1 ], last_nightly_run_on: THURSDAY - 1)
      termtime_budget = create_reimbursements_budget(name: "Termtime props", cost_centre: termtime)
      create_reimbursements_expense(person: payee, budget: termtime_budget, status: Status::APPROVED)

      NightlyBatchJob.perform_now(today: THURSDAY)

      ready = mailer_calls(:approved_ready).sole.last
      assert_equal [ SECOND_EMAIL ], ready[:recipients]
      assert_equal THURSDAY, termtime.reload.last_nightly_run_on
    end
  end
end
