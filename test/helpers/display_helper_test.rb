require "test_helper"

class DisplayHelperTest < ActionView::TestCase
  include DisplayHelper
  include PretixHelper
  include MdHelper

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

  test "display_when says the weekday for a run that plays one day a week" do
    # A year-long range tells nobody when to turn up; "Every Friday" does.
    event = FactoryBot.build(:show, start_date: Date.new(2026, 9, 1), end_date: Date.new(2027, 6, 30),
                                    performance_weekdays: "5")

    assert_equal "Every Friday", display_when(event)
  end

  test "display_when falls back to the range when no performance days are set" do
    event = FactoryBot.build(:show, start_date: Date.new(2026, 3, 3), end_date: Date.new(2026, 3, 7))

    assert_equal "Tue 3 – Sat 7 Mar", display_when(event)
  end


  test "display_booking_url points at the pretix shop when tickets are shown" do
    event = FactoryBot.build(:show, slug: "the-crucible", is_public: true, pretix_shown: true, pretix_slug_override: nil)

    assert_equal "https://tickets.bedlamtheatre.co.uk/the-crucible/", display_booking_url(event)
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
