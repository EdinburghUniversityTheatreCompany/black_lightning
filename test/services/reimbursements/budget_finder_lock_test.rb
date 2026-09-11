require "test_helper"

module Reimbursements
  ##
  # The row lock, exercised rather than asserted. Its own file because it turns
  # transactional fixtures OFF: the race needs two real connections, and a test
  # wrapped in one transaction can neither commit for the other thread to see
  # nor hold a lock the other thread waits on.
  #
  # Everything it writes therefore COMMITS, so the teardown has to survive a
  # failure anywhere — a leaked FinancialYear here surfaces as errors in the
  # setup of unrelated files, which is the poisoned-test-database class this
  # repo has been bitten by before.
  class BudgetFinderLockTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    self.use_transactional_tests = false

    setup do
      @centre = reimbursements_cost_centres(:fringe)
      # NOT active: nothing here reads FinancialYear.current, and a leaked
      # active year is the one that changes what other tests see.
      @year = FinancialYear.create!(label: "Fringe 2026")
      @area = create_reimbursements_area(name: "Cogito", financial_year: @year, cost_centre: @centre)
      @code = create_reimbursements_nominal_code(code: "432320", cost_centre: @centre,
                                                 label: "Marketing")
    end

    teardown do
      # The racer holds a transaction inserting a budget into the area this
      # deletes, and a failed test body releases the lock it was waiting on —
      # so join first or the delete races a commit. Its own exception is not
      # this teardown's to raise: the test's failure is the one worth reading.
      begin
        @racer&.join(5)
      rescue StandardError
        nil
      end
      # Each guard stands alone: a setup that failed part way through leaves
      # the later ivars nil, and a teardown that nil-derefs abandons the rows
      # created before it.
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
        # Only that the racer is serialised behind this transaction, which its
        # own INSERT's foreign-key lock on the area row would also do. The
        # outcome assertions below are what prove the store's lock: without it
        # the racer reads an empty area, and creates its own line the moment
        # this one commits.
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
