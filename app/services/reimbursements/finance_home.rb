module Reimbursements
  ##
  # The finance home page's figures, each read off the reader its linked screen
  # uses so the two agree. Totals are GROSS +amount+ ("how much money is about to
  # move", what EUSA pays), never the ex-VAT figure the budget rollups use. The
  # store comes scoped to the selected year and cost centre.
  class FinanceHome
    # Over-budget lines and unattributed rows named before linking to the full list.
    PREVIEW_ROWS = 5

    # The two counts on the /admin dashboard tile, which every admin loads:
    # plain counts off the table, since the store's #expenses preloads every
    # receipt. Unscoped, as the tile has no selectors.
    def self.tile_counts
      { pending: Expense.where(status: Status::PENDING).count,
        approved: Expense.where(status: Status::APPROVED).count }
    end

    attr_reader :store, :cost_centre

    def initialize(store:, cost_centre: nil)
      @store = store
      @cost_centre = cost_centre
    end

    # --- The claims queue ---------------------------------------------------

    def awaiting_owner = queue[:awaiting_owner]

    def to_approve = queue[:to_approve]

    def approved = queue[:approved]

    def awaiting_owner_total = claim_total(awaiting_owner)

    def to_approve_total = claim_total(to_approve)

    # What the next batch would pay: BatchProcessor moves every claim it takes
    # to Submitted, so Approved means unbatched.
    def approved_total = claim_total(approved)

    # --- The last batch -----------------------------------------------------

    # The latest batch by BACS date, then by id for undated ones.
    def last_batch
      return @last_batch if defined?(@last_batch)

      @last_batch = store.batches_for_cost_centre
                         .max_by { |batch| [ batch.date_sent || Date.new(0), batch.id ] }
    end

    def last_batch_expenses
      @last_batch_expenses ||=
        last_batch ? claims.select { |expense| expense.batch_id == last_batch.record_id } : []
    end

    def last_batch_total = claim_total(last_batch_expenses)

    # --- The EUSA ledger ----------------------------------------------------

    # Ledger rows no budget accounts for. Their total is net, so it can be negative.
    def unattributed = @unattributed ||= store.unattributed_actuals

    def unattributed_count = unattributed.size

    def unattributed_total = EusaActual.net(unattributed)

    def unattributed_preview = unattributed.first(PREVIEW_ROWS)

    # --- Budget health ------------------------------------------------------

    # Worst first, over the same budgets the Overview's headline counts.
    def over_budget_lines
      @over_budget_lines ||= store.budgets_with_actuals
                                  .select(&:over_budget?)
                                  .sort_by { |budget| budget.remaining }
    end

    def over_budget_count = over_budget_lines.size

    def over_budget_preview = over_budget_lines.first(PREVIEW_ROWS)

    # --- The nightly reminder run -------------------------------------------

    def reminder_cost_centres
      @reminder_cost_centres ||=
        cost_centre ? [ cost_centre ] : CostCentre.order(:name).to_a
    end

    private

    def claims
      @claims ||= store.expenses_for_cost_centre
    end

    def queue
      @queue ||= begin
        pending = claims.select(&:pending?)
        ReviewSupport.split_queue(claims, OwnerReview.unmet_gate_expense_ids(pending))
      end
    end

    def claim_total(expenses)
      expenses.sum { |expense| expense.amount || 0 }
    end
  end
end
