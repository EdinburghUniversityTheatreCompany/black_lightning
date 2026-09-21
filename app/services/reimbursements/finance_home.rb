module Reimbursements
  ##
  # The figures the finance home page prints — the portal's front door for the
  # business manager.
  #
  # Every figure here is read off an EXISTING reader and totalled the way the
  # screen it links to totals it: the queue splits come from
  # ReviewSupport.split_queue (so the counts match the Review tabs), the
  # over-budget count is taken over store.budgets_with_actuals (so it matches
  # the Overview's own headline), and the unattributed net goes through
  # EusaActual.net (so it matches the Ledger). This class assembles; it does
  # not invent a second reading of anything.
  #
  # The totals are GROSS +amount+, not amount_excl_vat, because every one of
  # them answers "how much money is about to move" — which is what EUSA pays
  # and what the batch and Review screens already print. The budget rollups
  # elsewhere use the ex-VAT figure for the different question of what a line
  # has cost; the two are not interchangeable and this one must not be swapped
  # for the other.
  #
  # Scoped exactly as the pages it links to are: the store it is given is
  # already built for the selected financial year and cost centre, so a home
  # page filtered to one pot totals that pot. +cost_centres+ is the exception,
  # being a reminder schedule rather than money.
  class FinanceHome
    # How many over-budget lines and unattributed ledger rows the page names
    # before it stops and links to the full list. Enough to act on without
    # turning the front door into a second copy of the Overview.
    PREVIEW_ROWS = 5

    # The two counts the /admin dashboard tile prints, read straight off the
    # table rather than through the store.
    #
    # That is deliberate and not a shortcut: the tile sits on a page EVERY
    # admin loads, and DatabaseStore#expenses eagerly attaches every claim's
    # receipt blobs — the right cost for the Review queue, an absurd one for
    # two numbers. These are plain status counts and need no preloads.
    #
    # Unscoped, because the tile is not inside the portal's year or cost-centre
    # selectors and so has no scope to honour; it matches the home page's own
    # default, which is every centre.
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

    # What the next batch would pay. An Approved claim is by definition not in
    # a batch yet: BatchProcessor moves every claim it takes to Submitted, so
    # "approved" and "approved and unbatched" are the same set.
    def approved_total = claim_total(approved)

    # --- The last batch -----------------------------------------------------

    # The most recent batch by BACS date, falling back to insertion order for
    # the batches that carry no date. Nil before the first batch is built.
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

    # Ledger rows no budget's figures account for. NET, not a sum of debits:
    # the figure can legitimately be negative (more unattributed income than
    # spend), which is why the count is printed beside it.
    def unattributed = @unattributed ||= store.unattributed_actuals

    def unattributed_count = unattributed.size

    def unattributed_total = EusaActual.net(unattributed)

    def unattributed_preview = unattributed.first(PREVIEW_ROWS)

    # --- Budget health ------------------------------------------------------

    # Lines with nothing left against their current plan, worst first. Taken
    # over the same budgets the Overview's own headline counts, so the two
    # pages can never disagree about how many there are.
    def over_budget_lines
      @over_budget_lines ||= store.budgets_with_actuals
                                  .select(&:over_budget?)
                                  .sort_by { |budget| budget.remaining }
    end

    def over_budget_count = over_budget_lines.size

    def over_budget_preview = over_budget_lines.first(PREVIEW_ROWS)

    # --- The nightly reminder run -------------------------------------------

    # The cost centres whose reminder schedule this page reports: the selected
    # one, or every centre when none is selected (the "all centres" default
    # every finance list has).
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
