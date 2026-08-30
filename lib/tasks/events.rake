namespace :events do
  desc "Read events.price into structured ticket_prices. Dry by default; APPLY=1 writes."
  task backfill_ticket_prices: :environment do
    apply = ENV["APPLY"] == "1"

    puts apply ? "Applying." : "Dry run — nothing will be written. Re-run with APPLY=1 to write."
    puts

    summary = Event::TicketPriceBackfill.call(apply: apply)

    puts "Considered:          #{summary.considered} event(s) with a price and no bands yet"
    puts "Readable:            #{summary.parsed}"
    puts "Before decimalisation: #{summary.pre_decimal} (refused on the date, not the string)"
    puts "Unreadable:          #{summary.unreadable}"
    puts

    if summary.parsed_samples.any?
      puts "What each readable string became:"
      summary.parsed_samples.sort.each { |raw, parsed| puts "  #{raw.inspect} -> #{parsed}" }
      puts
    end

    if summary.unreadable_counts.any?
      puts "Refused, most common first — check these are the ones you expect:"
      summary.unreadable_counts.sort_by { |raw, count| [ -count, raw ] }
             .each { |raw, count| puts "  #{count.to_s.rjust(5)}  #{raw.inspect}" }
      puts
    end

    puts apply ? "Done. price was not touched on any row." : "Nothing written."
  end
end
