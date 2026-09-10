require "test_helper"
require Rails.root.join("db/migrate/20260911100300_backfill_reimbursements_areas")

module Reimbursements
  # Exercises BackfillReimbursementsAreas#down directly — it's plain Ruby
  # (no DDL), so instantiating the migration class and calling #down works
  # fine against the already-migrated schema-loaded test database.
  class AreaBackfillMigrationTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    test "down refuses when an area carries a hand-set initial_budget" do
      budget = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!
      budget.reload.area.update!(initial_budget: 500)

      error = assert_raises(ActiveRecord::IrreversibleMigration) { BackfillReimbursementsAreas.new.down }
      assert_match(/hand-set initial_budget/, error.message)

      # Refusing means refusing — nothing was touched.
      assert_equal 1, Area.count
      assert_not_nil budget.reload.area_id
    end

    test "down refuses when an area's name is not reproducible from any of its budgets" do
      budget = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!
      area = budget.reload.area
      # Renaming the only budget leaves nothing that reproduces "Cogito".
      budget.update!(name: "Something else: Marketing")

      error = assert_raises(ActiveRecord::IrreversibleMigration) { BackfillReimbursementsAreas.new.down }
      assert_match(/nothing in the backfill would have created/, error.message)

      assert_equal 1, Area.count
      assert_equal area.id, budget.reload.area_id
    end

    # Area.delete_all bypasses has_many :forecasts, dependent: :destroy, so an
    # area whose agreed total was revised (a forecast, not initial_budget) got
    # past both other guards and died on a raw Mysql2 FK violation instead of
    # the friendly refusal.
    test "down refuses when an area carries a forecast of its own" do
      budget = create_reimbursements_budget(name: "Cogito: Marketing")
      AreaBackfill.run!
      area = budget.reload.area
      BudgetForecast.create!(area: area, amount: 750, date: Date.current, reason: "Committee")

      error = assert_raises(ActiveRecord::IrreversibleMigration) { BackfillReimbursementsAreas.new.down }
      assert_match(/forecast/, error.message)

      assert_equal 1, Area.count
      assert_equal area.id, budget.reload.area_id
    end

    test "down still unwinds a pristine backfill" do
      alice = create_reimbursements_person(name: "Alice", email: "alice@example.com")
      a = create_reimbursements_budget(name: "Cogito: Marketing")
      b = create_reimbursements_budget(name: "Cogito: Other")
      a.sync_owner_ids!([ alice.id ])
      AreaBackfill.run!

      BackfillReimbursementsAreas.new.down

      assert_nil a.reload.area_id
      assert_nil b.reload.area_id
      assert_equal 0, Area.count
      assert_equal 0, AreaOwner.count
      # The budget's own owner row survives — that's what makes this reversal exact.
      assert_equal [ alice.record_id ], a.own_owners.map(&:record_id)
    end
  end
end
