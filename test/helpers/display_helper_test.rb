require "test_helper"

class DisplayHelperTest < ActionView::TestCase
  include DisplayHelper
  include TimeHelper
  include PretixHelper
  include MdHelper

  # The fits are written out independently of the helper, so the sweeps compare
  # the layout it chose against an independent reading.
  def side_height(cast, crew, stride)
    qr = cast <= crew
    [ cast * stride + (qr ? DisplayHelper::CREDITS_QR_HEIGHT : 0),
      crew * stride + (qr ? 0 : DisplayHelper::CREDITS_QR_HEIGHT) ].max
  end

  def flow_height(cast, crew, stride)
    sections = [ cast, crew ].count(&:positive?)
    headings = sections * DisplayHelper::CREDITS_HEADING_HEIGHT +
               (sections > 1 ? DisplayHelper::CREDITS_SECTION_GAP : 0)
    ((headings + (cast + crew) * stride) / 2.0).ceil
  end

  def fits?(mode, cast, crew, size)
    stride = DisplayHelper::CREDITS_ROW_STRIDES.fetch(size)
    if mode == :flowed
      flow_height(cast, crew, stride) <= DisplayHelper::CREDITS_COLUMN_HEIGHT - DisplayHelper::CREDITS_QR_HEIGHT
    else
      side_height(cast, crew, stride) <= DisplayHelper::CREDITS_LIST_HEIGHT
    end
  end

  def largest_fit(mode, cast, crew)
    DisplayHelper::CREDITS_ROW_STRIDES.keys.find { |size| fits?(mode, cast, crew, size) }
  end

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
    assert_equal "Sun 11 – Thu 15 Oct, 7.30pm", display_when(run_of_five)
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

    assert_equal "Sun 11 Oct, 8pm", display_when(event)
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

  test "event_page_path uses the subclass route" do
    show = FactoryBot.create(:show, slug: "the-crucible")

    assert_equal "/shows/the-crucible", event_page_path(show)
  end

  # resources :events is index-only, so polymorphic_path raises, and a raise mid-render blanks the screen.
  test "event_page_path falls back to the listing for an event with no show route" do
    event = Event.new(id: 1, slug: "mystery")

    assert_equal events_path, event_page_path(event)
  end

  test "display_plain_text renders the markdown away instead of printing its source" do
    body = "## A heading\n\nSome **bold** text with a [link](https://example.com).\n"

    text = display_plain_text(body, length: 320)

    assert_equal "A heading Some bold text with a link.", text
    assert_no_match(/[#*\[\]]|https:/, text)
  end

  test "display_plain_text escapes exactly once" do
    text = display_plain_text("Gilbert & Sullivan", length: 320)

    assert_equal "Gilbert &amp; Sullivan", text
  end

  test "display_plain_text truncates" do
    text = display_plain_text(("word " * 200), length: 60)

    assert_operator text.length, :<=, 60
    assert_match(/\.\.\.\z/, text)
  end

  test "display_title_size steps down as the title gets longer" do
    short = display_title_size("The Crucible")
    medium = display_title_size("Richard O'Brien's The Rocky Horror Show")
    long = display_title_size("A" * 120)

    assert_equal "text-8xl", short
    assert_not_equal short, medium, "a title that cannot fit one line should step down"
    assert_not_equal medium, long, "a very long title should step down again"
  end

  # Cast beside Company unless flowing buys bigger names; the QR goes under the
  # shorter list, normally the cast (bottom left).
  test "display_credits_layout keeps a balanced show side by side, the QR under the cast" do
    [ [ 1, 2 ], [ 8, 12 ], [ 10, 10 ], [ 12, 12 ], [ 18, 18 ] ].each do |cast, crew|
      layout = display_credits_layout(cast, crew)

      assert_equal :side_by_side, layout[:mode], "#{cast} cast / #{crew} crew is balanced enough to stay in two lists"
      assert layout[:qr_in_cast_column], "#{cast} cast / #{crew} crew should carry the QR left"
    end
    assert_equal "text-5xl", display_credits_layout(8, 12)[:name_size]
  end

  # Side by side sizes off the longer list, so a lopsided show wastes a column.
  test "display_credits_layout flows a lopsided show, and the names get bigger for it" do
    { [ 3, 18 ] => "text-4xl", [ 18, 2 ] => "text-5xl", [ 16, 3 ] => "text-5xl",
      [ 5, 14 ] => "text-5xl", [ 0, 15 ] => "text-5xl" }.each do |(cast, crew), expected|
      layout = display_credits_layout(cast, crew)

      assert_equal :flowed, layout[:mode], "#{cast} cast / #{crew} crew wastes a column side by side"
      assert_equal expected, layout[:name_size], "#{cast} cast / #{crew} crew"
      # The QR is a footer under both columns, so its height comes off the flow.
      assert_equal DisplayHelper::CREDITS_COLUMN_HEIGHT - DisplayHelper::CREDITS_QR_HEIGHT, layout[:flow_height]
    end
  end

  # Whichever layout it picks must be the one that prints the names bigger.
  test "display_credits_layout never picks the layout with the smaller type" do
    sizes = DisplayHelper::CREDITS_ROW_STRIDES.keys

    (0..20).each do |cast|
      (0..20).each do |crew|
        chosen = display_credits_layout(cast, crew)
        other = largest_fit(chosen[:mode] == :flowed ? :side_by_side : :flowed, cast, crew)

        next if other.nil?

        assert_operator sizes.index(chosen[:name_size]), :<=, sizes.index(other),
                        "#{cast} cast / #{crew} crew took #{chosen[:mode]} at #{chosen[:name_size]}, " \
                        "when the other layout would have printed #{other}"
      end
    end
  end

  # Whichever column carries the QR must fit its names AND the code: an 18-name
  # cast fits text-2xl alone and does not once the QR is under it.
  test "display_credits_layout never picks a size the QR does not fit at" do
    (0..18).each do |cast|
      (0..18).each do |crew|
        layout = display_credits_layout(cast, crew)

        assert fits?(layout[:mode], cast, crew, layout[:name_size]),
               "#{cast} cast / #{crew} crew #{layout[:mode]} at #{layout[:name_size]} leaves no room for the QR"
        assert_equal(cast <= crew, layout[:qr_in_cast_column]) if layout[:mode] == :side_by_side
      end
    end
  end

  # A wrapping name or an oversized company defeats the row arithmetic. The cap is
  # the guarantee: the column under the QR never gets the QR's height, so the list
  # loses its tail, not the code.
  test "display_credits_layout always reserves the QR's height from the list it sits under" do
    [ [ 4, 9 ], [ 18, 18 ], [ 40, 40 ] ].each do |cast, crew|
      layout = display_credits_layout(cast, crew)

      assert_equal :side_by_side, layout[:mode], "#{cast}/#{crew} was expected to stay in two lists"

      carrying, other = layout.values_at(:cast_list_height, :crew_list_height)
      carrying, other = other, carrying unless layout[:qr_in_cast_column]

      assert_equal DisplayHelper::CREDITS_COLUMN_HEIGHT - DisplayHelper::CREDITS_QR_HEIGHT, carrying,
                   "#{cast}/#{crew}: the column under the QR must give up its height"
      assert_equal DisplayHelper::CREDITS_COLUMN_HEIGHT, other,
                   "#{cast}/#{crew}: the other column keeps its full height"
    end
  end

  # Past the scale it shrinks fully rather than clipping from a size that never
  # fitted, and anchors to the top only once the names stop fitting.
  test "display_credits_layout shrinks a company beyond the screen to the smallest size and anchors it to the top" do
    layout = display_credits_layout(30, 30)

    assert_equal DisplayHelper::CREDITS_ROW_STRIDES.keys.last, layout[:name_size]
    assert_equal "content-start", layout[:block_position]
    assert_equal "content-center", display_credits_layout(4, 6)[:block_position]
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
