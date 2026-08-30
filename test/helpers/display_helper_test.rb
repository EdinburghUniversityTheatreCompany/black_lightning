require "test_helper"

class DisplayHelperTest < ActionView::TestCase
  include DisplayHelper
  include TimeHelper
  include PretixHelper
  include MdHelper

  # The two fits, written out again rather than called through the helper, so the
  # sweep below compares the layout it chose against an independent reading.
  def side_by_side_size(cast, crew)
    qr = cast <= crew
    DisplayHelper::CREDITS_ROW_STRIDES.find { |_, stride|
      [ cast * stride + (qr ? DisplayHelper::CREDITS_QR_HEIGHT : 0),
        crew * stride + (qr ? 0 : DisplayHelper::CREDITS_QR_HEIGHT) ].max <= DisplayHelper::CREDITS_LIST_HEIGHT
    }&.first
  end

  def flowed_size(cast, crew)
    sections = [ cast, crew ].count(&:positive?)
    headings = sections * DisplayHelper::CREDITS_HEADING_HEIGHT +
               (sections > 1 ? DisplayHelper::CREDITS_SECTION_GAP : 0)
    room = DisplayHelper::CREDITS_COLUMN_HEIGHT - DisplayHelper::CREDITS_QR_HEIGHT
    DisplayHelper::CREDITS_ROW_STRIDES.find { |_, stride|
      ((headings + (cast + crew) * stride) / 2.0).ceil <= room
    }&.first
  end

  test "display_date_range collapses a single day" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 3))

    assert_equal "Tue 3 Mar", display_date_range(event)
  end

  test "display_date_range drops the repeated month" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_date_range(event)
  end

  test "display_date_range keeps both months when the run crosses one" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 30), end_date: Date.new(2026, 4, 2))

    assert_equal "Mon 30 Mar – Thu 2 Apr", display_date_range(event)
  end

  # Mick's ask: five nights in a row is a range, not the next night of five.
  test "display_when collapses a consecutive run into one range" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 10, 11), end_date: Date.new(2026, 10, 15))
    (0..4).each do |offset|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.new(2026, 10, 11) + offset).to_time.change(hour: 19, min: 30))
    end

    assert_equal "Sun 11 – Thu 15 Oct, 7.30pm", display_when(event)
  end

  # The whole run, not the part still to come -- Mick's call. The board states
  # the run the way the poster does.
  test "display_when states the whole run even once it has started" do
    event = FactoryBot.create(:show, start_date: Date.current - 2, end_date: Date.current + 2)
    (-2..2).each do |offset|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.current + offset).to_time.change(hour: 19, min: 30))
    end

    assert_equal "#{date_span(Date.current - 2, Date.current + 2)}, 7.30pm", display_when(event)
  end

  test "display_when names a single night" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 10, 11), end_date: Date.new(2026, 10, 11))
    FactoryBot.create(:event_occurrence, event: event, starts_at: Time.zone.local(2026, 10, 11, 20, 0))

    assert_equal "Sun 11 Oct, 8pm", display_when(event)
  end

  # The Improverts. Their raw range is "Sep 4 - Jun 30", which tells nobody when
  # to turn up -- the exact string display_when exists to avoid.
  test "display_when names the weekday for a standing weekly fixture" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 9, 4), end_date: Date.new(2027, 6, 30))
    6.times do |week|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.new(2026, 9, 4) + (week * 7)).to_time.change(hour: 19, min: 30))
    end

    assert_equal "Every Friday, 7.30pm", display_when(event)
  end

  # A Season's occurrences are opening hours, and the close is the half that
  # says when somebody has to be out.
  test "display_when prints the span when an occurrence states its own end" do
    season = FactoryBot.create(:season, start_date: Date.new(2026, 8, 30), end_date: Date.new(2026, 9, 2))
    FactoryBot.create(:event_occurrence, event: season,
                      starts_at: Time.zone.local(2026, 8, 30, 10, 0),
                      ends_at: Time.zone.local(2026, 8, 30, 23, 0))

    assert_equal "Sun 30 Aug, 10am – 11pm", display_when(season)
  end

  # A show states a curtain time and a running time, not an end per night, so
  # printing a derived "7.30pm – 9.45pm" on every line would be noise.
  test "display_when prints a bare curtain when the end is only derived" do
    show = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7),
                                    duration_minutes: 135)
    FactoryBot.create(:event_occurrence, event: show, starts_at: Time.zone.local(2026, 3, 4, 19, 30))

    assert_equal "Wed 4 Mar, 7.30pm", display_when(show)
  end

  # Every archive event has no performances, so this is the path almost all of
  # them take, and it has to keep printing what it printed before.
  test "display_when falls back to the range when nothing is scheduled" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_when(event)
  end

  # Neither one run nor a weekly fixture, and nothing on today: the board states
  # the span and the event page carries the real dates.
  test "display_when falls back to the range for an irregular set of dates" do
    event = FactoryBot.create(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))
    [ 0, 2, 4 ].each do |offset|
      FactoryBot.create(:event_occurrence, event: event,
                        starts_at: (Date.new(2026, 3, 3) + offset).to_time.change(hour: 19, min: 30))
    end

    assert_equal "Tue 3 – Sat 7 Mar", display_when(event, on: Date.new(2026, 3, 1))
  end

  # A festival whose hours change by the day has no single run to state, and the
  # bare date range says nothing about when it is open. The stretch covering
  # today is what somebody in front of the screen can act on.
  test "display_when states the block covering today when there is no single run" do
    season = FactoryBot.create(:season, start_date: Date.new(2026, 8, 30), end_date: Date.new(2026, 9, 2))
    [ [ 30, 8, 10, 23 ], [ 31, 8, 10, 23 ], [ 1, 9, 12, 25 ], [ 2, 9, 12, 22 ] ].each do |day, month, open_h, close_h|
      FactoryBot.create(:event_occurrence, event: season,
                        starts_at: Time.zone.local(2026, month, day, open_h),
                        ends_at: Time.zone.local(2026, month, day) + close_h.hours)
    end

    assert_equal "Sun 30 – Mon 31 Aug, 10am – 11pm", display_when(season, on: Date.new(2026, 8, 31))
    assert_equal "Tue 1 – Wed 2 Sep, 12pm – 1am", display_when(season, on: Date.new(2026, 9, 1))
  end

  # The column is a fixed 256px on a screen read from across a room, and the
  # derived price string ("£10 / £8 concessions / £7 members") truncates in it.
  test "display_price collapses structured bands to fit the board" do
    event = FactoryBot.build(:show, ticket_prices: [
      { "category" => "standard", "amount" => "10" },
      { "category" => "concession", "amount" => "8" },
      { "category" => "member", "amount" => "7" }
    ])

    assert_equal "£10/8/7", display_price(event)
  end

  test "display_price keeps the pence where there are any" do
    event = FactoryBot.build(:show, ticket_prices: [ { "category" => "standard", "amount" => "4.50" } ])

    assert_equal "£4.50", display_price(event)
  end

  test "display_price says Free rather than £0" do
    event = FactoryBot.build(:show, ticket_prices: [ { "category" => "standard", "amount" => "0" } ])

    assert_equal "Free", display_price(event)
  end

  # Every archive event has no bands, so this is the path almost all of them take.
  test "display_price falls back to whatever was typed" do
    event = FactoryBot.build(:show, price: "Pay what you can")

    assert_equal "Pay what you can", display_price(event)
  end

  test "display_booking_url points at the pretix shop when tickets are shown" do
    event = FactoryBot.build(:show, slug: "the-crucible", is_public: true, pretix_shown: true, pretix_slug_override: nil)

    assert_equal "https://tickets.bedlamtheatre.co.uk/the-crucible/", display_booking_url(event)
  end

  test "display_programme_url uses the linked programme when there is one" do
    event = FactoryBot.build(:show, digital_programme_url: "https://example.com/programme.pdf")

    assert_equal "https://example.com/programme.pdf", display_programme_url(event)
  end

  # A footer that appears for one show and vanishes for the next reads as a
  # broken slide from across the room, so the code always resolves to something.
  test "display_programme_url falls back to the event's own page" do
    show = FactoryBot.create(:show, slug: "the-crucible", digital_programme_url: nil)

    assert_equal "http://test.host/shows/the-crucible", display_programme_url(show)
  end

  test "event_page_path uses the subclass route" do
    show = FactoryBot.create(:show, slug: "the-crucible")

    assert_equal "/shows/the-crucible", event_page_path(show)
  end

  # resources :events is index-only, so polymorphic_path would raise -- and a
  # raise while rendering this screen is a blank box office, not a 500 page.
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

  # A long title must step down a size rather than be cut off -- the poster
  # page's whole job is naming the show.
  test "display_title_size steps down as the title gets longer" do
    short = display_title_size("The Crucible")
    medium = display_title_size("Richard O'Brien's The Rocky Horror Show")
    long = display_title_size("A" * 120)

    assert_equal "text-8xl", short
    assert_not_equal short, medium, "a title that cannot fit one line should step down"
    assert_not_equal medium, long, "a very long title should step down again"
  end

  test "display_title_size never returns a truncating class" do
    %w[Short Medium\ length\ title].each do |title|
      assert_no_match(/truncate/, display_title_size(title))
    end
  end

  # The QR lands in the column with room to spare, which for a normal show is
  # the cast -- putting it bottom left.
  test "display_credits_layout puts the QR under the shorter list" do
    assert display_credits_layout(8, 12)[:qr_in_cast_column], "8 cast against 12 crew should carry it left"
    assert display_credits_layout(12, 12)[:qr_in_cast_column], "an even split should still go left"
  end

  test "display_credits_layout leaves a normal show side by side at the largest size" do
    layout = display_credits_layout(8, 12)

    assert_equal :side_by_side, layout[:mode]
    assert_equal "text-5xl", layout[:name_size]
  end

  # Cast beside Company is the clearer read, so it is what a show gets unless
  # flowing actually buys bigger names.
  test "display_credits_layout keeps a balanced show side by side" do
    [ [ 1, 2 ], [ 8, 12 ], [ 10, 10 ], [ 12, 12 ], [ 18, 18 ] ].each do |cast, crew|
      assert_equal :side_by_side, display_credits_layout(cast, crew)[:mode],
                   "#{cast} cast / #{crew} crew is balanced enough to stay in two lists"
    end
  end

  # Side by side sizes off the LONGER list, so a lopsided show wastes a whole
  # column and shrinks every name to fit the other one into half the screen.
  test "display_credits_layout flows a lopsided show, and the names get bigger for it" do
    { [ 3, 18 ] => "text-4xl", [ 18, 2 ] => "text-5xl", [ 16, 3 ] => "text-5xl",
      [ 5, 14 ] => "text-5xl", [ 0, 15 ] => "text-5xl" }.each do |(cast, crew), expected|
      layout = display_credits_layout(cast, crew)

      assert_equal :flowed, layout[:mode], "#{cast} cast / #{crew} crew wastes a column side by side"
      assert_equal expected, layout[:name_size], "#{cast} cast / #{crew} crew"
    end
  end

  # The whole reason for choosing between them: whichever it picks has to be the
  # one that can print the names bigger.
  test "display_credits_layout never picks the layout with the smaller type" do
    sizes = DisplayHelper::CREDITS_ROW_STRIDES.keys

    (0..20).each do |cast|
      (0..20).each do |crew|
        chosen = display_credits_layout(cast, crew)
        other = chosen[:mode] == :flowed ? side_by_side_size(cast, crew) : flowed_size(cast, crew)

        next if other.nil?

        assert_operator sizes.index(chosen[:name_size]), :<=, sizes.index(other),
                        "#{cast} cast / #{crew} crew took #{chosen[:mode]} at #{chosen[:name_size]}, " \
                        "when the other layout would have printed #{other}"
      end
    end
  end

  # The point of the pixel arithmetic: whichever column carries the QR has to fit
  # its names AND the code, or the code goes off the bottom of a screen nobody is
  # watching. An 18-name cast fits text-2xl on its own and does not once the QR
  # is under it.
  test "display_credits_layout never picks a size the QR does not fit at" do
    (0..18).each do |cast|
      (0..18).each do |crew|
        layout = display_credits_layout(cast, crew)
        stride = DisplayHelper::CREDITS_ROW_STRIDES.fetch(layout[:name_size])
        qr = DisplayHelper::CREDITS_QR_HEIGHT

        if layout[:mode] == :flowed
          sections = [ cast, crew ].count(&:positive?)
          headings = sections * DisplayHelper::CREDITS_HEADING_HEIGHT +
                     (sections > 1 ? DisplayHelper::CREDITS_SECTION_GAP : 0)
          needed = ((headings + (cast + crew) * stride) / 2.0).ceil

          assert_operator needed, :<=, DisplayHelper::CREDITS_COLUMN_HEIGHT - qr,
                          "#{cast} cast / #{crew} crew flowed at #{layout[:name_size]} leaves no room for the QR"
        else
          tallest = [ cast * stride + (layout[:qr_in_cast_column] ? qr : 0),
                      crew * stride + (layout[:qr_in_cast_column] ? 0 : qr) ].max

          assert_operator tallest, :<=, DisplayHelper::CREDITS_LIST_HEIGHT,
                          "#{cast} cast / #{crew} crew at #{layout[:name_size]} overflows by " \
                          "#{tallest - DisplayHelper::CREDITS_LIST_HEIGHT}px"
        end
      end
    end
  end

  # A long enough name wraps, and a company bigger than the scale can serve
  # overflows outright -- neither of which row arithmetic can see coming. The cap
  # is the unconditional guarantee underneath it: the column carrying the QR is
  # never allowed the QR's own height, whatever the names do, so the list loses
  # its tail rather than the code being pushed off the screen.
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

  # The flowed layout takes the QR off the top of what it has to fill, rather
  # than under one column, because a balanced flow leaves neither column spare.
  test "display_credits_layout takes the QR's height out of the flow" do
    layout = display_credits_layout(3, 18)

    assert_equal :flowed, layout[:mode]
    assert_equal DisplayHelper::CREDITS_COLUMN_HEIGHT - DisplayHelper::CREDITS_QR_HEIGHT, layout[:flow_height]
  end

  # Past the scale it shrinks as far as it can rather than clipping from a size
  # that never fitted.
  test "display_credits_layout falls to the smallest size for a company beyond the screen" do
    assert_equal DisplayHelper::CREDITS_ROW_STRIDES.keys.last, display_credits_layout(30, 30)[:name_size]
  end

  test "display_credits_layout anchors to the top only once the names stop fitting" do
    assert_equal "content-center", display_credits_layout(4, 6)[:block_position]
    assert_equal "content-start", display_credits_layout(30, 30)[:block_position]
  end

  # Inline SVG rendered as a blank square on the Anthias player while looking
  # correct in a desktop browser, and survived an attempt to fix its intrinsic
  # sizing. A raster image has no such failure mode, and img-src already allows
  # data: so this needs nothing from the CSP.
  test "display_qr_code renders a PNG data URI, not an svg" do
    html = display_qr_code("https://example.com")

    assert_match(/<img[^>]+src="data:image\/png;base64,[A-Za-z0-9+\/=]+"/, html)
    assert_no_match(/<svg/, html)
  end

  # The Pi re-fetches these pages every few seconds, forever, and a QR for a
  # given URL never changes.
  test "display_qr_code caches the encoded image by url" do
    url = "https://example.com/cache-me"
    Rails.cache.delete(DisplayHelper.qr_cache_key(url))

    first = display_qr_code(url)

    assert Rails.cache.exist?(DisplayHelper.qr_cache_key(url)), "expected the encoded PNG to be cached"
    assert_equal first, display_qr_code(url), "a cache hit must produce identical markup"
  end

  test "two different urls do not share a cached image" do
    one = display_qr_code("https://example.com/one")
    two = display_qr_code("https://example.com/two")

    assert_not_equal one, two
  end

  test "display_qr_code labels itself for what the caller is asking people to scan" do
    assert_match(/alt="Scan to book"/, display_qr_code("https://example.com"))
    assert_match(/alt="Scan to read the news"/,
                 display_qr_code("https://example.com", label: "Scan to read the news"))
  end
end
