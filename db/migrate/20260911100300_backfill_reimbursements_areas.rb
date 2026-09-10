class BackfillReimbursementsAreas < ActiveRecord::Migration[8.1]
  def up
    Reimbursements::AreaBackfill.run!
  end

  # Detach, then drop the areas this migration created. The budgets' own owner
  # rows were deliberately kept (see AreaBackfill), so ownership returns to
  # exactly where it was — PROVIDED nothing has hand-edited the area tree
  # since. This is the first migration to write these tables, so today a
  # blanket wipe is equivalent to "what up created" — but the area edit form
  # (a later task) lets finance set a real agreed total and create areas of
  # its own, and a `down` after that must not destroy their work. Refuse
  # rather than silently drop it, the same shape as
  # 20260911100200_allow_area_budget_forecasts's refusal over area forecasts.
  def down
    concerns = []

    hand_totalled = Reimbursements::Area.where.not(initial_budget: nil).pluck(:name)
    concerns << "areas with a hand-set initial_budget (#{hand_totalled.join(', ')})" if hand_totalled.any?

    fabricated = []
    Reimbursements::Area.includes(:budgets).find_each do |area|
      reproducible = area.budgets.any? do |budget|
        match = Reimbursements::AreaBackfill::NAME_PATTERN.match(budget.name.to_s)
        match && match[:area].strip == area.name
      end
      fabricated << area.name unless reproducible
    end
    if fabricated.any?
      concerns << "areas nothing in the backfill would have created (#{fabricated.join(', ')})"
    end

    if concerns.any?
      raise ActiveRecord::IrreversibleMigration,
            "the area tree shows signs of hand-editing — #{concerns.join('; ')} — unwind by hand before rolling back"
    end

    Reimbursements::Budget.where.not(area_id: nil).update_all(area_id: nil)
    Reimbursements::AreaOwner.delete_all
    Reimbursements::Area.delete_all
  end
end
