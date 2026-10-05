##
# An event's performances read back as a person would describe them: five nights
# in a row is one range, a year of Fridays is "Every Friday" (a range would print
# "Sep 1 - Jun 30"). The whole run is described, not just what is still to come.
##
class Event::Schedule
  # One unbroken stretch of consecutive days sharing a curtain time.
  Block = Data.define(:starts_on, :ends_on, :time_of_day, :occurrences) do
    def single_day?
      starts_on == ends_on
    end
  end

  # Two dates a week apart are a short run, and three inside a fortnight are a
  # short run that happens to be weekly.
  WEEKLY_MINIMUM = 3
  WEEKLY_MINIMUM_SPAN = 14

  attr_reader :event, :occurrences

  def self.for(event)
    new(event)
  end

  def initialize(event)
    @event = event
    @occurrences = event.event_occurrences.select { |occurrence| occurrence.starts_at.present? }
                        .sort_by(&:starts_at)
  end

  def kind
    return :none if occurrences.empty?
    return :weekly if weekly?
    return :single if blocks.one? && blocks.first.single_day?
    return :range if blocks.one?

    :irregular
  end

  def blocks
    @blocks ||= build_blocks
  end

  # The hours every performance shares; nil when they differ.
  def time_of_day
    times = occurrences.map { |occurrence| time_key(occurrence) }.uniq

    times.one? ? times.first : nil
  end

  # A representative start, for formatting the shared time.
  def starts_at
    occurrences.first&.starts_at
  end

  def weekday
    return nil unless weekly?

    occurrences.first.on_date.wday
  end

  def weekday_name
    weekday && Date::DAYNAMES[weekday]
  end

  private

  # Grouped by curtain time first, then folded by consecutive date: a Saturday
  # matinee sorts between the evenings and would otherwise cut the run in three.
  def build_blocks
    occurrences.group_by { |occurrence| time_key(occurrence) }
               .flat_map { |time, group| consecutive_blocks(time, group) }
               .sort_by { |block| [ block.starts_on, block.time_of_day ] }
  end

  def consecutive_blocks(time, group)
    group.sort_by(&:starts_at).each_with_object([]) do |occurrence, built|
      last = built.last

      if last && occurrence.on_date == last.ends_on + 1
        built[-1] = last.with(ends_on: occurrence.on_date, occurrences: last.occurrences + [ occurrence ])
      elsif last && occurrence.on_date == last.ends_on
        # A duplicated row must not open a zero-length gap and a second block.
        built[-1] = last.with(occurrences: last.occurrences + [ occurrence ])
      else
        built << Block.new(starts_on: occurrence.on_date, ends_on: occurrence.on_date,
                           time_of_day: time, occurrences: [ occurrence ])
      end
    end
  end

  # Gaps may be any multiple of a week, so a reading week does not break it.
  def weekly?
    return false if occurrences.length < WEEKLY_MINIMUM
    return false if time_of_day.nil?

    dates = occurrences.map(&:on_date).uniq

    return false if dates.length < WEEKLY_MINIMUM
    return false if (dates.last - dates.first).to_i <= WEEKLY_MINIMUM_SPAN
    return false unless dates.map(&:wday).uniq.one?

    dates.each_cons(2).all? { |from, to| ((to - from).to_i % 7).zero? }
  end

  # Both ends, not just the curtain: the view prints a block's hours from its first
  # occurrence, so a Season open 12pm-1am one day and 12pm-10pm the next would
  # advertise 1am for both.
  def time_key(occurrence)
    [ occurrence.starts_at.strftime("%H:%M"), end_key(occurrence) ].compact.join("-")
  end

  def end_key(occurrence)
    return nil if occurrence.ends_at.blank?

    # Days apart, so a close after midnight differs from one before it.
    offset = (occurrence.ends_at.to_date - occurrence.starts_at.to_date).to_i

    "#{occurrence.ends_at.strftime('%H:%M')}+#{offset}"
  end
end
