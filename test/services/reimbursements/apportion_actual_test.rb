require "test_helper"

module Reimbursements
  class ApportionActualTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    setup do
      @store = DatabaseStore.new
      @actual = create_reimbursements_eusa_actual(credit: 4000)
      @a = create_reimbursements_budget(name: "Show A", budget_type: "Income")
      @b = create_reimbursements_budget(name: "Show B", budget_type: "Income")
    end

    test "splits a row into shares that sum to it" do
      @store.apportion_actual!(@actual.id, [
        { budget_id: @a.id, amount: BigDecimal("2500") },
        { budget_id: @b.id, amount: BigDecimal("1500") }
      ])

      assert_equal 2, @actual.reload.allocations.count
      assert_nil @actual[:budget_id]
      assert_predicate @actual, :apportioned?
    end

    test "refuses shares that do not sum to the row" do
      assert_raises(DatabaseStore::ApportionmentMismatchError) do
        @store.apportion_actual!(@actual.id, [ { budget_id: @a.id, amount: BigDecimal("3880") } ])
      end

      assert_empty @actual.reload.allocations
    end

    test "refuses a row that is not apportionable" do
      debit = create_reimbursements_eusa_actual(debit: 500)

      assert_raises(DatabaseStore::NotApportionableError) do
        @store.apportion_actual!(debit.id, [ { budget_id: @a.id, amount: BigDecimal("500") } ])
      end

      assert_empty debit.reload.allocations
    end

    test "refuses an empty split rather than detaching the row from everything" do
      assert_raises(DatabaseStore::ApportionmentMismatchError) do
        @store.apportion_actual!(@actual.id, [])
      end

      assert_empty @actual.reload.allocations
    end

    test "removing an apportionment restores the row to unlinked" do
      @store.apportion_actual!(@actual.id, [ { budget_id: @a.id, amount: BigDecimal("4000") } ])
      @store.remove_apportionment!(@actual.id)

      assert_empty @actual.reload.allocations
      assert_predicate @actual, :apportionable?
      assert_nil @actual.reconciliation_status
    end

    # The stamp is what the ledger view and the CSV read to say the row is
    # accounted for — without it the row reads as an ordinary unlinked credit
    # while its income already sits on budgets.
    test "a split row is stamped apportioned and carries no budget of its own" do
      @store.apportion_actual!(@actual.id, [ { budget_id: @a.id, amount: BigDecimal("4000") } ])

      assert_equal EusaActual::STATUS_APPORTIONED, @actual.reload.reconciliation_status
      assert_nil @actual[:budget_id]
      assert_not_predicate @actual, :offset?
    end

    # The parts have to add up to the figure the ROLLUPS read — credits less
    # debits — not to the stored net column, which is parsed separately from
    # the export's own Net cell and can disagree with the pair.
    test "the sum is checked against credits less debits, not the stored net" do
      row = create_reimbursements_eusa_actual(credit: 1000, debit: 100)
      row.update_column(:net, -1000)

      @store.apportion_actual!(row.id, [ { budget_id: @a.id, amount: BigDecimal("900") } ])

      assert_equal 1, row.reload.allocations.count
    end

    # An offsetting leg nets to zero, so a split of one would invent income.
    test "refuses an offsetting leg" do
      leg = create_reimbursements_eusa_actual(credit: 900,
                                              reconciliation_status: EusaActual::STATUS_OFFSET)

      assert_raises(DatabaseStore::NotApportionableError) do
        @store.apportion_actual!(leg.id, [ { budget_id: @a.id, amount: BigDecimal("900") } ])
      end
    end

    # Splitting twice would double the income. The guard is re-taken inside
    # the transaction under a row lock, so the second write is refused even
    # when the caller's own check was taken before the first one committed.
    test "refuses a second split of a row already apportioned" do
      @store.apportion_actual!(@actual.id, [ { budget_id: @a.id, amount: BigDecimal("4000") } ])

      assert_raises(DatabaseStore::NotApportionableError) do
        @store.apportion_actual!(@actual.id, [ { budget_id: @b.id, amount: BigDecimal("4000") } ])
      end

      assert_equal 1, @actual.reload.allocations.count
    end

    # All-or-nothing: a half-written split leaves the row reading as unlinked
    # while some of its shares are already on budgets.
    test "a share naming no budget writes nothing at all" do
      assert_raises(ActiveRecord::RecordInvalid) do
        @store.apportion_actual!(@actual.id, [
          { budget_id: @a.id, amount: BigDecimal("2500") },
          { budget_id: nil, amount: BigDecimal("1500") }
        ])
      end

      assert_empty @actual.reload.allocations
      assert_predicate @actual, :apportionable?
    end
  end
end
