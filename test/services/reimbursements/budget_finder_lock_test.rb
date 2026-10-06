require "test_helper"

module Reimbursements
  ##
  # The row lock, exercised rather than asserted. Non-transactional, since the race needs two
  # real connections, so everything it writes COMMITS: the teardown must survive a failure
  # anywhere, or a leaked FinancialYear poisons unrelated tests.
  class BudgetFinderLockTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    self.use_transactional_tests = false

    setup do
      @centre = reimbursements_cost_centres(:fringe)
      # Not active: a leaked active year changes what other tests see.
      @year = FinancialYear.create!(label: "Fringe 2026")
      @area = create_reimbursements_area(name: "Cogito", financial_year: @year, cost_centre: @centre)
      @code = create_reimbursements_nominal_code(code: "432320", cost_centre: @centre,
                                                 label: "Marketing")
    end

    teardown do
      # Join the racer first, or the delete below races its commit. Its own exception is not
      # the teardown's to raise: the test's failure is the one worth reading.
      begin
        @racer&.join(5)
      rescue StandardError
        nil
      end
      # Each guard stands alone: a setup that failed part way leaves later ivars nil.
      Budget.where(area_id: @area.id).delete_all if @area&.persisted?
      Area.where(id: @area.id).delete_all if @area&.persisted?
      NominalCode.where(id: @code.id).delete_all if @code&.persisted?
      FinancialYear.where(id: @year.id).delete_all if @year&.persisted?
    end

    test "a creation racing another takes the line the winner created" do
      running = Queue.new
      winner = nil

      Area.transaction do
        Area.lock.find(@area.id)
        @racer = racing_creation(running)
        assert_equal :running, running.pop
        # Only that the racer waits (its INSERT's FK lock would do that too). The outcome
        # assertions prove the store's lock: without it the racer reads an empty area and
        # creates its own line the moment this one commits.
        refute @racer.join(1), "the racing creation did not wait for this transaction"

        winner = Budget.create!(area: @area, name: "Marketing", nominal_code: "432320",
                                cost_centre: @centre, financial_year: @year)
      end

      assert_equal winner.id, @racer.value.id, "the racer created its own line for one (area, code)"
      assert_equal 1, Budget.where(area_id: @area.id).count
    end

    private

    def racing_creation(running)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          running << :running
          Reimbursements.build_store.find_or_create_budget_for_area!(
            area_id: @area.id, nominal_code: "432320", name: "Marketing",
            cost_centre: @centre, financial_year: @year
          )
        end
      end
    end
  end
end
