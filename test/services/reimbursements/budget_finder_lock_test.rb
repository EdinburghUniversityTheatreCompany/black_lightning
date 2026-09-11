require "test_helper"

module Reimbursements
  ##
  # The row lock, proved rather than asserted. Its own file because it turns
  # transactional fixtures OFF: the race needs two real connections, and a test
  # wrapped in one transaction can neither commit for the other thread to see
  # nor hold a lock the other thread waits on. Its rows are removed by hand for
  # the same reason.
  class BudgetFinderLockTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    self.use_transactional_tests = false

    setup do
      @centre = reimbursements_cost_centres(:fringe)
      @year = FinancialYear.create!(label: "Fringe 2026", active: true)
      @area = create_reimbursements_area(name: "Cogito", financial_year: @year, cost_centre: @centre)
      @code = create_reimbursements_nominal_code(code: "432320", cost_centre: @centre,
                                                 label: "Marketing")
    end

    teardown do
      Budget.where(area_id: @area.id).delete_all
      Area.where(id: @area.id).delete_all
      NominalCode.where(id: @code.id).delete_all
      FinancialYear.where(id: @year.id).delete_all
    end

    test "a creation racing another waits for the area's row lock and takes its line" do
      running = Queue.new
      racer = nil
      winner = nil

      Area.transaction do
        Area.lock.find(@area.id)
        racer = racing_creation(running)
        assert_equal :running, running.pop
        refute racer.join(1), "the racing creation did not wait for the area's row lock"

        winner = Budget.create!(area: @area, name: "Marketing", nominal_code: "432320",
                                cost_centre: @centre, financial_year: @year)
      end

      assert_equal winner.id, racer.value.id, "the racer created its own line for one (area, code)"
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
