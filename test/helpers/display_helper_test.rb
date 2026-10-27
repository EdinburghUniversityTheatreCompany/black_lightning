require "test_helper"

class DisplayHelperTest < ActionView::TestCase
  include DisplayHelper
  include TimeHelper
  include PretixHelper

  def run_of_five(from: Date.new(2026, 10, 11))
    event = FactoryBot.create(:show, start_date: from, end_date: from + 4)

    (0..4).each do |offset|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (from + offset).in_time_zone.change(hour: 19, min: 30))
    end

    event
  end

  test "display_date_range collapses what the two dates share" do
    { [ Date.new(2026, 3, 3), Date.new(2026, 3, 3) ] => "Tue 3 Mar",
      [ Date.new(2026, 3, 3), Date.new(2026, 3, 7) ] => "Tue 3 – Sat 7 Mar",
      [ Date.new(2026, 3, 30), Date.new(2026, 4, 2) ] => "Mon 30 Mar – Thu 2 Apr" }.each do |(from, to), expected|
      assert_equal expected, display_date_range(FactoryBot.build(:show, start_date: from, end_date: to)), expected
    end
  end

  test "display_when collapses a consecutive run into one range" do
    assert_equal "Sun 11 – Thu 15 Oct, 7.30pm", display_when(run_of_five, on: Date.new(2026, 10, 1))
  end

  test "display_when states the whole run even once it has started" do
    event = FactoryBot.create(:show, start_date: Date.current - 2, end_date: Date.current + 2)
    (-2..2).each do |offset|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.current + offset).in_time_zone.change(hour: 19, min: 30))
    end

    assert_equal "#{date_span(Date.current - 2, Date.current + 2)}, 7.30pm", display_when(event)
  end

  test "display_when names a single night" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 10, 11), end_date: Date.new(2026, 10, 11))
    FactoryBot.create(:event_occurrence, event: event, starts_at: Time.zone.local(2026, 10, 11, 20, 0))

    assert_equal "Sun 11 Oct, 8pm", display_when(event, on: Date.new(2026, 10, 11))
  end

  test "display_when names the weekday for a standing weekly fixture" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 9, 4), end_date: Date.new(2027, 6, 30))
    6.times do |week|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.new(2026, 9, 4) + (week * 7)).in_time_zone.change(hour: 19, min: 30))
    end

    assert_equal "Every Friday, 7.30pm", display_when(event)
  end

  # A Season's occurrences are opening hours, so the close is stated.
  test "display_when prints the span when an occurrence states its own end" do
    season = FactoryBot.create(:season, start_date: Date.new(2026, 8, 30), end_date: Date.new(2026, 9, 2))
    FactoryBot.create(:event_occurrence, event: season,
                      starts_at: Time.zone.local(2026, 8, 30, 10, 0),
                      ends_at: Time.zone.local(2026, 8, 30, 23, 0))

    assert_equal "Sun 30 Aug, 10am – 11pm", display_when(season, on: Date.new(2026, 8, 30))
  end

  # A show states a curtain and a running time, so a derived end would be noise.
  test "display_when prints a bare curtain when the end is only derived" do
    show = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7),
                                    duration_minutes: 135)
    FactoryBot.create(:event_occurrence, event: show, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_equal "Wed 4 Mar, 7.30pm", display_when(show, on: Date.new(2026, 3, 1))
  end

  # The path every archive event takes.
  test "display_when falls back to the range when nothing is scheduled" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_when(event)
  end

  # Scattered dates: the next one with its curtain time. A bare range drops the
  # time and implies every night in between.
  test "display_when names the next date for an irregular set of dates" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))
    [ 0, 2, 4 ].each do |offset|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.new(2026, 3, 3) + offset).in_time_zone.change(hour: 19, min: 30))
    end

    assert_equal "Tue 3 Mar, 7.30pm", display_when(event, on: Date.new(2026, 3, 1))
    assert_equal "Thu 5 Mar, 7.30pm", display_when(event, on: Date.new(2026, 3, 4))
  end

  # Half-entered list: the run is on but every listed performance has passed.
  test "display_when states the run once its only performance has passed" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 10, 11), end_date: Date.new(2026, 10, 20))
    FactoryBot.create(:event_occurrence, event: event,
                      starts_at: Date.new(2026, 10, 11).in_time_zone.change(hour: 19, min: 30))

    assert_equal "Sun 11 Oct, 7.30pm", display_when(event, on: Date.new(2026, 10, 11))
    assert_equal "Sun 11 – Tue 20 Oct", display_when(event, on: Date.new(2026, 10, 15))
  end

  test "display_when falls back to the range once every date has passed" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))
    [ 0, 2 ].each do |offset|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.new(2026, 3, 3) + offset).in_time_zone.change(hour: 19, min: 30))
    end

    assert_equal "Tue 3 – Sat 7 Mar", display_when(event, on: Date.new(2026, 3, 7))
  end

  # A matinee makes the schedule :irregular; both blocks are stated, in advance and mid-run alike.
  test "display_when states both curtain times for a run with a matinee" do
    event = run_of_five
    FactoryBot.create(:event_occurrence, event: event,
                      starts_at: Date.new(2026, 10, 15).in_time_zone.change(hour: 14, min: 30))

    [ Date.new(2026, 10, 1), Date.new(2026, 10, 13), Date.new(2026, 10, 15) ].each do |on|
      assert_equal "Sun 11 – Thu 15 Oct, 7.30pm\nThu 15 Oct, 2.30pm", display_when(event, on: on), on.to_s
    end
  end

  # Rocky Horror: 7pm Wed-Sat with midnight shows on Friday and Saturday. The
  # late show must be advertised.
  test "display_when states a late-show block alongside the evening run" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 9, 23), end_date: Date.new(2026, 9, 26))
    (23..26).each do |day|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: Time.zone.local(2026, 9, day, 19, 0))
    end
    [ 25, 26 ].each do |day|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: Time.zone.local(2026, 9, day, 23, 45))
    end

    expected = "Wed 23 – Sat 26 Sep, 7pm\nFri 25 – Sat 26 Sep, 11.45pm"

    assert_equal expected, display_when(event, on: Date.new(2026, 9, 1)), "in advance"
    assert_equal expected, display_when(event, on: Date.new(2026, 9, 26)), "and on the night"
  end

  # Past WHEN_MAX_BLOCKS only the block covering today is left.
  test "display_when falls back to the block covering today when there are too many" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 8))
    [ [ 3, 19 ], [ 5, 14 ], [ 7, 21 ] ].each do |day, hour|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: Time.zone.local(2026, 3, day, hour))
    end

    assert_equal 3, Event::Schedule.for(event.reload).blocks.size
    assert_equal "Thu 5 Mar, 2pm", display_when(event, on: Date.new(2026, 3, 5))
  end

  # A festival whose hours change by the day has no single run: state the stretch covering today.
  test "display_when states the block covering today when there is no single run" do
    season = FactoryBot.create(:season, start_date: Date.new(2026, 8, 30), end_date: Date.new(2026, 9, 2))
    [ [ 30, 8, 10, 23 ], [ 31, 8, 10, 23 ], [ 1, 9, 12, 25 ], [ 2, 9, 12, 22 ] ].each do |day, month, open_h, close_h|
      FactoryBot.create(:event_occurrence, event: season,
                        starts_at: Time.zone.local(2026, month, day, open_h),
                        ends_at: Time.zone.local(2026, month, day) + close_h.hours)
    end

    # Sun and Mon share hours so they fold; Tue (1am) and Wed (10pm) are separate blocks.
    assert_equal "Sun 30 – Mon 31 Aug, 10am – 11pm", display_when(season, on: Date.new(2026, 8, 31))
    assert_equal "Tue 1 Sep, 12pm – 1am", display_when(season, on: Date.new(2026, 9, 1))
    assert_equal "Wed 2 Sep, 12pm – 10pm", display_when(season, on: Date.new(2026, 9, 2))
  end

  # The board's column is a fixed 256px; the derived "£10 / £8 concessions / £7 members" truncates in it.
  test "display_price fits the board's fixed column" do
    { [ %w[standard 10], %w[concession 8], %w[member 7] ] => "£10/8/7",
      [ %w[standard 4.50] ] => "£4.50",
      [ %w[standard 0] ] => "Free" }.each do |bands, expected|
      prices = bands.map { |category, amount| { "category" => category, "amount" => amount } }

      assert_equal expected, display_price(FactoryBot.build(:show, ticket_prices: prices))
    end
    # The path every archive event takes (no bands): whatever was typed.
    assert_equal "Pay what you can", display_price(FactoryBot.build(:show, price: "Pay what you can"))
  end

  test "display_booking_url points at the pretix shop when tickets are shown" do
    event = FactoryBot.build(:show, slug: "the-crucible", is_public: true, pretix_shown: true, pretix_slug_override: nil)

    assert_equal "https://tickets.bedlamtheatre.co.uk/the-crucible/", display_booking_url(event)
  end

  test "display_programme_url uses the linked programme when there is one" do
    event = FactoryBot.build(:show, digital_programme_url: "https://example.com/programme.pdf")

    assert_equal "https://example.com/programme.pdf", display_programme_url(event)
  end

  # The programme QR always resolves to something.
  test "display_programme_url falls back to the event's own page" do
    show = FactoryBot.create(:show, slug: "the-crucible", digital_programme_url: nil)

    assert_equal "http://test.host/shows/the-crucible", display_programme_url(show)
  end

  # resources :events is index-only, so polymorphic_url raises, and a raise mid-render blanks the screen.
  test "display_event_url falls back to the listing for an event with no show route" do
    event = Event.new(id: 1, slug: "mystery")

    assert_equal events_url, display_event_url(event)
  end

  test "display_title_size steps down as the title gets longer" do
    short = display_title_size("The Crucible")
    medium = display_title_size("Richard O'Brien's The Rocky Horror Show")
    long = display_title_size("A" * 120)

    assert_equal "text-8xl", short
    assert_not_equal short, medium, "a title that cannot fit one line should step down"
    assert_not_equal medium, long, "a very long title should step down again"
  end

  # One list, biggest type first, then the fewest columns that fit one screen.
  # Entries are name/detail pairs, because the fit counts LINES (a long role
  # wraps), not people. The names are real-world lengths: synthetic "Person 1"
  # data hides exactly the wrapping this layout exists to catch.
  CAST = [
    [ "Eleanor Ashworth", "Actor" ], [ "Tom O'Sullivan", "Actor" ], [ "Priya Natarajan", "Actor" ],
    [ "Callum Reid", "Actor" ], [ "Maeve Fitzpatrick", "Actor" ], [ "Daniel Okonkwo", "Actor" ],
    [ "Sofia Marchetti", "Actor" ], [ "Robin Whitfield", "Actor" ], [ "Grace Lindqvist", "Actor" ],
    [ "Aaron Doyle", "Actor" ], [ "Nina Petrova", "Actor" ], [ "Josh Beckett", "Actor" ]
  ].freeze
  CREW = [
    [ "Rory Blackwood", "Director" ], [ "Hannah Meehan", "Producer" ], [ "Sam O'Rourke", "Stage Manager" ],
    [ "Leah Connolly", "Deputy Stage Manager" ], [ "Peter Nakamura", "Lighting Designer" ],
    [ "Aisha Kerr", "Sound Designer" ], [ "Michael Farrell", "Set Construction" ], [ "Erin Walsh", "Set Construction" ],
    [ "David Mulcahy", "Set Construction" ], [ "Claire Breen", "Costume Designer" ],
    [ "Sean Gallagher", "Assistant Technical Stage Manager" ],
    [ "Kate Donnelly", "Assistant Technical Stage Manager" ], [ "Liam O'Carroll", "Master Carpenter" ],
    [ "Fiona Slattery", "Props Manager" ], [ "Mark Herron", "Make-up Artist" ], [ "Jodie Palmer", "Hair and Wigs" ],
    [ "Owen Fitzgerald", "Front of House" ], [ "Niamh Kinsella", "Front of House" ], [ "Paul Doherty", "Publicity" ],
    [ "Aoife Brennan", "Publicity" ], [ "Ryan Tierney", "Photography" ], [ "Ella Sweeney", "Videography" ],
    [ "Jack Corcoran", "Musical Director" ], [ "Megan Byrne", "Rehearsal Pianist" ],
    [ "Conor Leahy", "Fight Choreography" ], [ "Zoe Kavanagh", "Choreography" ],
    [ "Harry Dunne", "Wardrobe Assistant" ], [ "Lucy Hegarty", "Prompt" ], [ "Ben Corrigan", "Technical Operator" ],
    [ "Sarah Foley", "Technical Operator" ]
  ].freeze

  # The fits are checked against the numbers measured in Chrome at 1920x1080,
  # not by re-running the helper's own arithmetic. A second copy of the model
  # agrees with the model; only measurements disagree with it.
  #
  # Measured by the screen's owner on the real page: 42 people (these cast and
  # crew lists) fill three columns at text-2xl, and 70 people only fit four
  # columns at text-base. Both are the layout this helper must return, so a
  # change to CREDITS_CHAR_EM or the strides that perturbs them is a bug.
  MEASURED_FITS = {
    [ 42, 3 ] => "text-2xl",
    [ 70, 4 ] => "text-base"
  }.freeze

  def credits_lines_at(cast, crew, size, columns)
    chars = (DisplayHelper::CREDITS_CONTENT_WIDTH - (columns - 1) * DisplayHelper::CREDITS_COLUMN_GAP) / columns
    per_line = (chars / (DisplayHelper::CREDITS_CHAR_EM * DisplayHelper::CREDITS_FONT_PX.fetch(size))).floor
    (cast + crew).sum { |(name, detail)| credits_entry_lines("#{name} #{detail}", per_line) }
  end

  def credits_fits?(cast, crew, size, columns)
    stride = DisplayHelper::CREDITS_ROW_STRIDES.fetch(size)
    sections = [ cast, crew ].count(&:any?)
    heading_cost = sections * DisplayHelper::CREDITS_HEADING_HEIGHT +
                   (sections > 1 ? DisplayHelper::CREDITS_SECTION_GAP : 0)
    (heading_cost + credits_lines_at(cast, crew, size, columns) * stride) / columns.to_f <=
      DisplayHelper::CREDITS_WINDOW_HEIGHT
  end

  test "display_credits_layout picks the biggest type first, then the fewest columns" do
    layout = display_credits_layout(CAST, CREW)

    # 42 entries with the long technical roles in them: text-3xl overruns the
    # window in every column count, text-2xl needs three columns, not two.
    assert_equal "text-2xl", layout[:name_size]
    assert_equal 3, layout[:columns]
    assert credits_fits?(CAST, CREW, layout[:name_size], layout[:columns]), "the chosen fit must fit"
    assert_not credits_fits?(CAST, CREW, "text-2xl", 2), "two columns of text-2xl must not fit, or a column was wasted"
    assert_not credits_fits?(CAST, CREW, "text-3xl", 4), "bigger type must be tried and rejected first"
  end

  # The two sizes measured on the real page. If the model drifts, it drifts here
  # first, and the screen scrolls when nobody is watching it.
  test "display_credits_layout reproduces the sizes measured in Chrome" do
    MEASURED_FITS.each do |(count, columns), size|
      company = (CAST + CREW)
      company += Array.new(count - company.length) { [ "Sean Gallagher", "Assistant Technical Stage Manager" ] } if count > company.length
      cast, crew = count > 42 ? [ [], company ] : [ CAST, CREW ]
      assert_equal count, cast.length + crew.length

      assert_equal({ name_size: size, columns: columns, fits: true }, display_credits_layout(cast, crew),
                   "#{count} people were measured fitting #{columns} columns at #{size}")
    end
  end

  test "display_credits_layout shrinks the type only when no column count fits" do
    layout = display_credits_layout(CAST, CREW.take(18))

    # Fewer roles, so the type goes up: text-5xl still does not fit anywhere.
    assert_equal "text-4xl", layout[:name_size]
    assert credits_fits?(CAST, CREW.take(18), "text-4xl", layout[:columns]), "the chosen fit must fit"
    assert_not credits_fits?(CAST, CREW.take(18), "text-4xl", 2), "two columns of text-4xl must not fit"
    2.upto(4) do |columns|
      assert_not credits_fits?(CAST, CREW.take(18), "text-5xl", columns),
                 "text-5xl in #{columns} columns must not fit, or the size-first rule was skipped"
    end
  end

  test "display_credits_layout counts lines, not people" do
    # "Assistant Technical Stage Manager" is 34 characters: it wraps at the
    # bigger sizes, and the layout must charge for every wrapped line or it
    # promises a fit that scrolls.
    long_crew = Array.new(8) { [ "Sean Gallagher", "Assistant Technical Stage Manager" ] }
    short_crew = Array.new(8) { [ "Aisha Kerr", "Sound Designer" ] }
    long_layout = display_credits_layout(CAST.take(6), long_crew)
    short_layout = display_credits_layout(CAST.take(6), short_crew)

    assert_equal "text-5xl", short_layout[:name_size]
    # Same head-count, same type size: the long roles simply need another column.
    assert_equal long_layout[:name_size], short_layout[:name_size]
    assert long_layout[:columns] > short_layout[:columns],
           "a role that wraps must cost the layout something, not just disappear"
    assert credits_fits?(CAST.take(6), long_crew, long_layout[:name_size], long_layout[:columns])
  end

  # A long real name and a long real role, the pair that breaks a character
  # count: the name alone fills a line, so the role cannot share it.
  test "credits_lines charges for where the words actually break" do
    per_line = 12 # 3 columns of text-base is about this many characters

    assert_equal 1, credits_entry_lines("Jo Prompt", per_line)
    # "Christopher" is 11 of the 12, so "MacAllister" starts a second line and
    # "Assistant" a third: three words, one line each, not a length divided.
    assert_equal 3, credits_entry_lines("Christopher MacAllister Assistant", per_line)
    assert_equal 4, credits_entry_lines("Christopher MacAllister Assistant Technical", per_line)
    # A word wider than the column stays on its own line rather than vanishing.
    assert_equal 2, credits_entry_lines("Unfeasiblylongsurname Actor", per_line)
  end

  test "display_credits_layout falls back to the smallest type in four columns, with the marquee as the net" do
    layout = display_credits_layout(CAST, Array.new(90) { [ "Sean Gallagher", "Assistant Technical Stage Manager" ] })

    assert_equal({ name_size: "text-base", columns: 4, fits: false }, layout)
    assert_not credits_fits?(CAST, Array.new(90) { [ "Sean Gallagher", "Assistant Technical Stage Manager" ] },
                             "text-base", 4),
               "this is the marquee's case: the fit is allowed to fail, and the scroll takes over"
  end

  test "display_credits_layout works for an all-cast or all-crew show" do
    assert_equal({ name_size: "text-5xl", columns: 2, fits: true }, display_credits_layout(CAST.first(5), []))
    assert_equal({ name_size: "text-5xl", columns: 2, fits: true }, display_credits_layout([], CREW.first(5)))
  end

  # The tail-slack div the template renders for the scroll's final hold is
  # conditional on `fits`: inside a track that fits, its 3.5rem makes the track
  # taller than the window and the marquee crawls though nothing is left to
  # show. The template only renders it when the helper says the fit failed.
  test "display_credits_layout reports whether the marquee is needed" do
    assert display_credits_layout(CAST, CREW)[:fits], "the measured fit must report fits"
    assert_not display_credits_layout(CAST, Array.new(90) { [ "Sean Gallagher", "Assistant Technical Stage Manager" ] })[:fits],
               "the marquee's fallback case must report does-not-fit"
  end

  # The chrome is pinned twice: here (the helper's window arithmetic) and in the
  # pages controller test (the rendered markup). Both must hold the same value.
  test "credits window arithmetic matches the pinned chrome" do
    assert_equal (1080 - DisplayHelper::CREDITS_CHROME_REM * 16).floor, DisplayHelper::CREDITS_WINDOW_HEIGHT
  end

  # SVG rendered as a blank square on Anthias; a raster image has no such failure mode.
  test "display_qr_code renders a PNG data URI, not an svg" do
    html = display_qr_code("https://example.com")

    assert_match(/<img[^>]+src="data:image\/png;base64,[A-Za-z0-9+\/=]+"/, html)
    assert_no_match(/<svg/, html)
  end

  # The Pi re-fetches forever and a given URL's code never changes.
  test "display_qr_code caches the encoded image by url" do
    url = "https://example.com/cache-me"
    Rails.cache.delete(DisplayHelper.qr_cache_key(url))

    first = display_qr_code(url)

    assert Rails.cache.exist?(DisplayHelper.qr_cache_key(url)), "expected the encoded PNG to be cached"
    assert_equal first, display_qr_code(url), "a cache hit must produce identical markup"
    assert_not_equal first, display_qr_code("https://example.com/other"), "another url must not share the cached image"
  end

  test "display_qr_code labels itself for what the caller is asking people to scan" do
    assert_match(/alt="Scan to book"/, display_qr_code("https://example.com"))
    assert_match(/alt="Scan to read the news"/,
                 display_qr_code("https://example.com", label: "Scan to read the news"))
  end
end
