namespace :pretix do
  desc "Switch performance sync on for every future event. Dry by default; APPLY=1 writes."
  task enable_performance_sync: :environment do
    apply = ENV["APPLY"] == "1"

    puts apply ? "Applying." : "Dry run — nothing will be written. Re-run with APPLY=1 to write."
    puts

    summary = Pretix::PerformanceSyncEnablement.new.call(apply: apply)

    puts "Considered:       #{summary.considered} event(s) whose run has not ended"
    puts "Switched on:      #{summary.enabled.length}"
    puts "Already on:       #{summary.already_on.length}"
    puts "Skipped:          #{summary.not_performances.length} (seasons — their dates are opening times)"
    puts

    if summary.enabled.any?
      puts "Switched on:"
      summary.enabled.each { |event| puts "  #{event.pretix_slug.ljust(45)} #{event.start_date}  #{event.name}" }
      puts
      puts "Any of these without a ticket shop yet will simply wait, and say so on"
      puts "their admin page. Nothing errors and nothing is deleted."
      puts
    end

    puts apply ? "Done." : "Nothing written."
  end
end
