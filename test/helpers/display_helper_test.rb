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

  test "display_qr_code renders an inline svg with no xml declaration" do
    svg = display_qr_code("https://example.com")

    assert_match(/\A<svg /, svg)
    assert_no_match(/<\?xml/, svg)
    assert_match(/viewbox=/i, svg)
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

  # Anthias renders these pages in an older engine than a desktop browser. An
  # <svg> with a viewBox but no width/height is sized purely by CSS, and inside
  # a flex container several engines then compute the content's intrinsic size
  # as zero -- a correctly sized, completely blank square.
  test "display_qr_code carries explicit width and height matching its viewBox" do
    svg = display_qr_code("https://example.com")

    extent = svg[/viewBox="0 0 (\d+) \d+"/, 1]
    assert extent.present?, "expected a viewBox"
    assert_match(/width="#{extent}"/, svg)
    assert_match(/height="#{extent}"/, svg)
  end

  test "display_qr_code labels itself for what the caller is asking people to scan" do
    assert_match(/aria-label="Scan to book"/, display_qr_code("https://example.com"))
    assert_match(/aria-label="Scan to read the news"/,
                 display_qr_code("https://example.com", label: "Scan to read the news"))
  end
end
