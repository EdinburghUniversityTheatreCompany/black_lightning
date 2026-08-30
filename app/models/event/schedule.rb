##
# An event's performances, read back as the shape a human would describe them in.
#
# Five nights in a row is "Wed 11 - Sun 15 October", not five rows; a year of
# Fridays is "Every Friday", because a date range there prints "Sep 1 - Jun 30",
# the exact string the box office screen exists to avoid. This is what the
# retired performance_weekdays column used to say, now derived from real dates
# rather than a hand-set field -- and it knows the curtain time.
#
# The whole run is described, not the part still to come: Mick's call. The board
# advertises the run as the poster does.
##
class Event::Schedule
  # One unbroken stretch of consecutive days sharing a curtain time.
  Block = Data.define(:starts_on, :ends_on, :time_of_day, :occurrences) do
    def single_day?
      starts_on == ends_on
    end
  end

  # A standing fixture has to look like one. Two dates a week apart are a short
  # run; three inside a fortnight are a short run that happens to be weekly. The
  # Improverts play for most of the academic year.
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

  # The curtain time every performance shares, as "19:30"; nil when they differ.
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

  ##
  # The performances a collapsed range would hide: the relaxed night, the press
  # night, the one with a post-show discussion. Whatever the rest of the run is
  # rendered as, these have to be named or the access information is lost.
  ##
  def exceptions
    occurrences.select { |occurrence| occurrence.access_flags.any? || occurrence.note.present? }
  end

  private

  ##
  # Consecutive dates at the same curtain time fold together; a gap starts a new
  # block.
  #
  # Grouped BY TIME first, rather than walked in one chronological pass. A
  # Saturday matinee sorts in between the Friday and Saturday evenings, so a
  # single pass would let it cut the evening run in three -- the matinee is its
  # own block, and the run either side of it is still one run.
  ##
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
        # Two performances the same day at the same time is not a thing, but a
        # duplicated row must not create a zero-length gap and a second block.
        built[-1] = last.with(occurrences: last.occurrences + [ occurrence ])
      else
        built << Block.new(starts_on: occurrence.on_date, ends_on: occurrence.on_date,
                           time_of_day: time, occurrences: [ occurrence ])
      end
    end
  end

  ##
  # Every performance on the same weekday, at the same time, a week apart or a
  # multiple of one -- so a reading week or a cancelled night does not stop it
  # reading as "every Friday".
  ##
  def weekly?
    return false if occurrences.length < WEEKLY_MINIMUM
    return false if time_of_day.nil?

    dates = occurrences.map(&:on_date).uniq

    return false if dates.length < WEEKLY_MINIMUM
    return false if (dates.last - dates.first).to_i <= WEEKLY_MINIMUM_SPAN
    return false unless dates.map(&:wday).uniq.one?

    dates.each_cons(2).all? { |from, to| ((to - from).to_i % 7).zero? }
  end

  ##
  # Both ends, not just the curtain. The view prints one block's hours from its
  # first occurrence, so a Season open 12pm-1am on Tuesday and 12pm-10pm on
  # Wednesday would fold into one block and advertise Wednesday as closing at
  # 1am. Different hours are a different block.
  ##
  def time_key(occurrence)
    [ occurrence.starts_at.strftime("%H:%M"), end_key(occurrence) ].compact.join("-")
  end

  def end_key(occurrence)
    return nil if occurrence.ends_at.blank?

    # Days apart, so a close after midnight does not read as the same hours as
    # one before it.
    offset = (occurrence.ends_at.to_date - occurrence.starts_at.to_date).to_i

    "#{occurrence.ends_at.strftime('%H:%M')}+#{offset}"
  end
end
