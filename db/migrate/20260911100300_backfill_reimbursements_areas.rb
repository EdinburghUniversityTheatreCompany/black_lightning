class BackfillReimbursementsAreas < ActiveRecord::Migration[8.1]
  def up
    created_area_ids = Reimbursements::AreaBackfill.run!
    # The backfill re-homes only the lines whose NAME reproduces their area, so
    # anything created, moved or imported into one comes back from what #down
    # recorded. A first run — every run that is not a re-migrate — has nothing
    # recorded to read.
    Reimbursements::AreaMembership.restore!
    # Only the areas THIS run created and the restore then emptied: the backfill
    # keys on the budget's year and centre while the record keys on the area's,
    # so a cross-year line is re-homed into a new area here and moved out again
    # by the restore, leaving an ownerless phantom in that year's pickers that
    # the next #down refuses over as hand-editing. Deliberately NOT a sweep of
    # every empty area — the area form has shipped, so an empty area is
    # something a person can mean to have.
    Reimbursements::Area.where(id: created_area_ids).where.missing(:budgets).destroy_all
  end

  # ROLLING THIS BACK ON A DATABASE THAT APPLIED IT BEFORE PHASE 2B: run
  # `db:migrate` FIRST. The recording column arrives in 20260911100250, pending
  # on such a database (lower version, so Rails applies it out of order), and
  # without it this raises AreaMembership::MissingRecordError mid-chain with
  # 20260911100400/500/600 already reverted. Nothing is lost and `db:migrate`
  # puts them back, but the rollback stops in an unexpected place.
  #
  # Detach, then drop the areas this migration created — the budgets' own owner
  # rows were deliberately kept (see AreaBackfill), so ownership returns to
  # where it was, PROVIDED nothing has hand-edited the area tree since. The
  # area edit form lets finance set a real agreed total and create areas of
  # their own, and a `down` after that must not destroy their work: refuse
  # rather than silently drop it, the shape
  # 20260911100200_allow_area_budget_forecasts already uses.
  def down
    concerns = []

    hand_totalled = Reimbursements::Area.where.not(initial_budget: nil).pluck(:name)
    concerns << "areas with a hand-set initial_budget (#{hand_totalled.join(', ')})" if hand_totalled.any?

    # Area.delete_all below bypasses has_many :forecasts, dependent: :destroy,
    # so a revised agreed total would otherwise get past both other guards and
    # die on a raw FK violation — and a revision is finance's work either way.
    forecast_revised = Reimbursements::Area.joins(:forecasts).distinct.pluck(:name)
    concerns << "areas carrying a forecast of their own (#{forecast_revised.join(', ')})" if
      forecast_revised.any?

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

    # Record before detaching and in one transaction with it: a detach whose
    # record did not land is the silent loss this exists to stop.
    ActiveRecord::Base.transaction do
      Reimbursements::AreaMembership.record!
      Reimbursements::Budget.where.not(area_id: nil).update_all(area_id: nil)
      Reimbursements::AreaOwner.delete_all
      Reimbursements::Area.delete_all
    end
  end
end
