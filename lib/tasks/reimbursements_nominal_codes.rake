namespace :reimbursements do
  desc "Seed each cost centre's nominal code list from the codes its budgets carry. Dry by default; APPLY=1 writes."
  task nominal_code_seed: :environment do
    apply = ENV["APPLY"] == "1"

    puts apply ? "Applying." : "Dry run — nothing will be written. Re-run with APPLY=1 to write."
    puts

    plan = Reimbursements::NominalCodeSeed.plan

    if plan.empty?
      puts "Nothing to seed — every code a budget carries is already listed."
    else
      plan.each do |entry|
        line = "  #{entry[:cost_centre].name.ljust(24)} #{entry[:code].ljust(12)} " \
               "#{entry[:budget_count]} budget(s) -> #{entry[:label].inspect}"
        if entry[:unplaced_count].positive?
          line += " (#{entry[:unplaced_count]} from budget(s) with no cost centre of their own, " \
                  "folded into the default centre)"
        end
        puts line
      end
      puts
      puts "#{plan.size} code(s) to seed."
    end
    puts

    if apply
      Reimbursements::NominalCodeSeed.apply!
      puts "Done. #{plan.size} nominal code(s) created."
    else
      puts "Nothing written."
    end
  end
end
