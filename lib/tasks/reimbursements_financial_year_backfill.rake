namespace :reimbursements do
  # One-off backfill for the financial-year rollout. Everything written before
  # financial years had a UI is unstamped: `budgets.financial_year_id`,
  # `budgets.cost_centre_id` and — where FinancialYear.current was nil at the
  # time — `expenses.financial_year_id` and `eusa_actuals.financial_year_id`.
  #
  # The reads tolerate that (DatabaseStore#in_year counts an unstamped row as
  # belonging to whichever year is being viewed, so nothing disappears), but the
  # tolerance is a safety net, not the destination: while rows are unstamped,
  # last year's lines show up in next year's budget list.
  #
  # Run once in production after deploying:
  #
  #   RAILS_ENV=production bin/rails reimbursements:financial_year_backfill
  #
  # Idempotent: it only touches rows whose column is NULL, so a second run is a
  # no-op and a partial run resumes cleanly. Dry-run first with:
  #
  #   RAILS_ENV=production bin/rails reimbursements:financial_year_backfill DRY_RUN=1
  desc "Backfill: stamp pre-financial-year reimbursements rows with a year and cost centre"
  task financial_year_backfill: :environment do
    dry_run = ENV["DRY_RUN"].present?

    year = Reimbursements::FinancialYear.current
    # No active year means the rollout's first step hasn't happened. Guessing
    # one here would file every historical budget under a year nobody chose,
    # and a budget's year is what the whole selector reads.
    if year.nil?
      abort "Refusing to run: no financial year is active. Create the year these rows belong to " \
            "under Reimbursements > Financial Years and make it active first."
    end

    cost_centre = Reimbursements::CostCentre.default
    abort "Refusing to run: no cost centre is configured. Add one under Settings first." if cost_centre.nil?

    if Reimbursements::CostCentre.count > 1
      # With a second pot live, "the first cost centre" stops being the only
      # answer, and mis-filing a budget sends its spend to the wrong pot.
      abort "Refusing to run: #{Reimbursements::CostCentre.count} cost centres are configured, so " \
            "which one an unstamped budget belongs to is a real question. Set budgets.cost_centre_id " \
            "by hand (or narrow this task) rather than having it guessed."
    end

    puts "Backfilling into #{year.label} / #{cost_centre.name}#{' (DRY RUN)' if dry_run}"

    counts = {
      "budgets (financial year)" => Reimbursements::Budget.where(financial_year_id: nil),
      "budgets (cost centre)" => Reimbursements::Budget.where(cost_centre_id: nil),
      "expenses" => Reimbursements::Expense.where(financial_year_id: nil),
      "EUSA actuals" => Reimbursements::EusaActual.where(financial_year_id: nil),
      "budget updates" => Reimbursements::BudgetUpdate.where(financial_year_id: nil)
    }

    counts.each do |label, scope|
      count = scope.count
      puts "  #{label}: #{count} unstamped"
      next if count.zero? || dry_run

      # update_all, not find_each: these are plain FK writes with no callbacks
      # to run, and a row-at-a-time loop over a season's expenses would be slow
      # for no gain.
      updated = if label == "budgets (cost centre)"
                  scope.update_all(cost_centre_id: cost_centre.id, updated_at: Time.current)
      else
                  scope.update_all(financial_year_id: year.id, updated_at: Time.current)
      end
      puts "    stamped #{updated}"
    end

    if dry_run
      puts "Dry run — nothing was written. Re-run without DRY_RUN=1 to apply."
    else
      puts "Done. Check the budgets list under each year to confirm the split looks right."
    end
  end
end
