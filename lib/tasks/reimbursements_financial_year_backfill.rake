namespace :reimbursements do
  # One-off backfill for the financial-year rollout: stamps the rows written before years had a
  # UI (budgets' year and cost centre, expenses' and EUSA actuals' year).
  #
  # DatabaseStore#in_year reads an unstamped row as belonging to the year being viewed, but
  # that is a safety net: until stamped, last year's lines show in next year's budget list.
  #
  # Idempotent (only NULL columns are touched), so a second run is a no-op. Dry-run first:
  #
  #   RAILS_ENV=production bin/rails reimbursements:financial_year_backfill DRY_RUN=1
  desc "Backfill: stamp pre-financial-year reimbursements rows with a year and cost centre"
  task financial_year_backfill: :environment do
    dry_run = ENV["DRY_RUN"].present?

    year = Reimbursements::FinancialYear.current
    # Guessing a year would file every historical budget under one nobody chose.
    if year.nil?
      abort "Refusing to run: no financial year is active. Create the year these rows belong to " \
            "under Reimbursements > Financial Years and make it active first."
    end

    cost_centre = Reimbursements::CostCentre.default
    abort "Refusing to run: no cost centre is configured. Add one under Settings first." if cost_centre.nil?

    if Reimbursements::CostCentre.count > 1
      # With a second pot, mis-filing a budget sends its spend to the wrong one.
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

      # update_all: plain FK writes, no callbacks to run.
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
