class BackfillReimbursementsAreas < ActiveRecord::Migration[8.1]
  def up
    Reimbursements::AreaBackfill.run!
    # The backfill re-homes only the lines whose NAME reproduces their area, so
    # anything created, moved or imported into one is restored from what #down
    # recorded instead. Nothing is recorded on a first run, which is every run
    # that is not a re-migrate.
    Reimbursements::AreaMembership.restore!
  end

  # ROLLING THIS BACK ON A DATABASE THAT APPLIED IT BEFORE PHASE 2B: run
  # `db:migrate` FIRST. The recording column arrives in 20260911100250, which is
  # pending on such a database (its version is lower, so Rails applies it out of
  # order), and without it #down raises AreaMembership::MissingRecordError —
  # mid-chain, with 20260911100400/500/600 already reverted. Nothing is lost and
  # `db:migrate` puts them back, but the rollback stops in an unexpected place.
  #
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

    # Area.delete_all below bypasses has_many :forecasts, dependent: :destroy,
    # so an area whose agreed total has been revised would otherwise get past
    # both other guards and die on a raw FK violation. A revision to an agreed
    # total is finance's work either way, the same thing
    # 20260911100200_allow_area_budget_forecasts refuses to drop.
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

    # Record before detaching, and in one transaction with it: a detach whose
    # record did not land is exactly the silent loss this exists to stop.
    ActiveRecord::Base.transaction do
      Reimbursements::AreaMembership.record!
      Reimbursements::Budget.where.not(area_id: nil).update_all(area_id: nil)
      Reimbursements::AreaOwner.delete_all
      Reimbursements::Area.delete_all
    end
  end
end
