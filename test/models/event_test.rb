# == Schema Information
#
# Table name: events
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *name*::                   <tt>string(255)</tt>
# *tagline*::                <tt>string(255)</tt>
# *slug*::                   <tt>string(255)</tt>
# *publicity_text*::         <tt>text(65535)</tt>
# *members_only_text*::      <tt>text(65535)</tt>
# *xts_id*::                 <tt>integer</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *is_public*::              <tt>boolean</tt>
# *image_file_name*::        <tt>string(255)</tt>
# *image_content_type*::     <tt>string(255)</tt>
# *image_file_size*::        <tt>integer</tt>
# *image_updated_at*::       <tt>datetime</tt>
# *start_date*::             <tt>date</tt>
# *end_date*::               <tt>date</tt>
# *venue_id*::               <tt>integer</tt>
# *season_id*::              <tt>integer</tt>
# *author*::                 <tt>string(255)</tt>
# *type*::                   <tt>string(255)</tt>
# *price*::                  <tt>string(255)</tt>
# *spark_seat_slug*::        <tt>string(255)</tt>
# *maintenance_debt_start*:: <tt>date</tt>
# *staffing_debt_start*::    <tt>date</tt>
# *proposal_id*::            <tt>integer</tt>
#--
# == Schema Information End
#++
require "test_helper"

class EventTest < ActionView::TestCase
  include TimeHelper

  setup do
    @event = FactoryBot.create(:event)
  end

  test "selection_collection" do
    assert_equal [ [ @event.name, @event.id ] ], Event.selection_collection
  end

  test "members_only_text_customised? distinguishes the unfilled template from real content" do
    event = Event.new
    event.members_only_text = "<!-- members-only-template — delete this line and write your notes -->\n\n#### About the show\n_prompt_"
    assert_not event.members_only_text_customised?, "the unfilled default template is not customised"

    event.members_only_text = "Our real post-show writeup"
    assert event.members_only_text_customised?

    event.members_only_text = ""
    assert_not event.members_only_text_customised?
    event.members_only_text = nil
    assert_not event.members_only_text_customised?
  end

  test "this_academic_year" do
    this_year_show = FactoryBot.create(:show, start_date: Date.current)
    old_show = FactoryBot.create(:show, start_date: @event.start_date.advance(years: -3))
    future_workshop = FactoryBot.create(:workshop, start_date: Date.current.advance(years: 1))

    assert_includes Event.this_academic_year, this_year_show
    assert this_year_show.this_academic_year?

    assert_not_includes Event.this_academic_year, old_show
    assert_not old_show.this_academic_year?

    assert_not_includes Event.this_academic_year, future_workshop
    assert_not future_workshop.this_academic_year?
  end

  test "thumb_image_url" do
    event = FactoryBot.create(:event, attach_image: false)
    assert_includes event.thumb_image_url, "active_storage_default-events-"
  end

  test "slideshow_image_url" do
    event = FactoryBot.create(:event, attach_image: false)
    assert_includes event.slideshow_image_url, "active_storage_default-events-"
  end

  test "date_range" do
    assert_equal time_range_string(@event.start_date, @event.end_date, true), @event.date_range(true)
  end

  test "simultaneous seasons" do
    season = FactoryBot.create(:season)
    assert_includes season.simultaneous_seasons, season
    show = FactoryBot.create(:show, start_date: season.end_date.advance(days: -1))
    assert_includes show.simultaneous_seasons, season
  end

  test "possible proposals for new event and existing event" do
    show = FactoryBot.build(:workshop, attach_proposal: false)

    long_ago_proposal = FactoryBot.create(:proposal, submission_deadline: show.start_date.advance(years: -5), status: :successful)
    current_proposal = FactoryBot.create(:proposal, submission_deadline: show.start_date.advance(days: -5), status: :successful)
    far_future_proposal = FactoryBot.create(:proposal, submission_deadline: show.start_date.advance(years: 5), status: :successful)

    unsuccessful_proposal = FactoryBot.create(:proposal, submission_deadline: show.start_date.advance(days: -5), status: :unsuccessful)

    # Before the show has dates, the possible proposals should be all successful proposals.
    assert_includes show.possible_proposals, long_ago_proposal
    assert_includes show.possible_proposals, current_proposal
    assert_includes show.possible_proposals, far_future_proposal
    assert_not_includes show.possible_proposals, unsuccessful_proposal

    # After the show has been saved and has dates, the dropdown should limit itself to proposals within one year of the start date.
    show.save

    assert_not_includes show.possible_proposals, long_ago_proposal
    assert_includes show.possible_proposals, current_proposal
    assert_not_includes show.possible_proposals, far_future_proposal
    assert_not_includes show.possible_proposals, unsuccessful_proposal
  end

  test "possible proposals for existing event with proposal attached" do
    show = FactoryBot.create(:show, attach_proposal: false)

    current_proposal = FactoryBot.create(:proposal, submission_deadline: show.start_date.advance(days: -5), status: :successful)
    far_future_proposal = FactoryBot.create(:proposal, submission_deadline: show.start_date.advance(years: 5), status: :successful)

    show.proposal = far_future_proposal

    assert_includes show.possible_proposals, current_proposal
    assert_includes show.possible_proposals, far_future_proposal
  end

  test "as_json" do
    @event.update!(venue: venues(:one), season: FactoryBot.create(:season))

    json = @event.as_json(include: [ :season ])

    assert json.is_a? Hash
    assert json.key? "venue"
    assert json.key? "season"
  end

  test "sets default members-only text field" do
    event = Event.new

    assert_equal "This is the default text for the members-only text field.", event.members_only_text
  end

  test "pretix slug override works" do
    @event.slug = "foo"
    assert_equal "foo", @event.pretix_slug

    @event.pretix_slug_override = "bar"
    assert_equal "bar", @event.pretix_slug
  end

  test "get author name list" do
    Rails.cache.delete(Event::AUTHOR_NAME_LIST_CACHE_KEY)

    show_1 = FactoryBot.create(:show, author: "Author 2")
    show_2 = FactoryBot.create(:show, author: "Author 1")

    assert_equal([ "Author 1", "Author 2" ], Event.author_name_list)

    # Updating an author should clear the cache and return the new list.
    show_1.update!(author: "Author 3")

    assert_equal([ "Author 1", "Author 3" ], Event.author_name_list)
  end

  test "automatically generates slug from name if blank" do
    event = FactoryBot.build(:event, name: "Test Event Name", slug: "")
    assert event.valid?
    assert_equal "test-event-name", event.slug
  end

  test "updates slug when name changes and slug was auto-generated" do
    event = FactoryBot.create(:event, name: "Original Name")
    original_slug = event.slug

    event.name = "New Event Name"
    event.valid?
    assert_not_equal original_slug, event.slug
    assert_equal "new-event-name", event.slug
  end

  test "does not update slug when name changes if slug was manually set" do
    event = FactoryBot.create(:event, name: "Original Name", slug: "custom-slug")

    event.name = "New Event Name"
    event.valid?
    assert_equal "custom-slug", event.slug
  end

  test "generates unique slugs when duplicates would occur" do
    event1 = FactoryBot.create(:event, name: "Test Event")
    event2 = FactoryBot.build(:event, name: "Test Event", slug: "")

    assert event2.valid?
    assert_equal "test-event", event1.slug
    assert_equal "test-event-1", event2.slug
  end

  test "generates a URL-safe slug from the name" do
    { 'Event with "Quotes" & Symbols!' => "event-with-quotes-and-symbols", "Événement spéciàl" => "evenement-special" }.each do |name, slug|
      event = FactoryBot.build(:event, name: name, slug: "")
      assert event.valid?, name
      assert_equal slug, event.slug, name
    end
  end

  test "slug uniqueness validation works case-insensitively" do
    FactoryBot.create(:event, slug: "test-slug")
    duplicate_event = FactoryBot.build(:event, slug: "TEST-SLUG")

    assert_not duplicate_event.valid?
    assert duplicate_event.errors[:slug].any? { |error| error.include?("already taken") }
  end

  test "validates end_date can equal start_date" do
    event = FactoryBot.build(:event, start_date: Date.current, end_date: Date.current)
    assert event.valid?
  end

  test "invalidates when end_date is before start_date" do
    event = FactoryBot.build(:event, start_date: Date.current, end_date: Date.current - 1.day)
    assert_not event.valid?
    assert_includes event.errors[:end_date], "must be after or equal to start date"
  end

  test "date range validation works with nil dates" do
    event = FactoryBot.build(:event, start_date: nil, end_date: Date.current)
    assert_not event.valid?
    assert_includes event.errors[:start_date], "must not be blank."
    assert_not_includes event.errors[:end_date], "must be after or equal to start date"
  end

  test "slug format" do
    [ "my event slug", "My-Event", "slug<tag>", "slug&amp", "slug/path", "slug?query", "slug#hash",
      "-leading-hyphen", "trailing-hyphen-" ].each do |slug|
      event = FactoryBot.build(:event, slug: slug)
      assert_not event.valid?, slug.inspect
      assert event.errors[:slug].any?, slug.inspect
    end
    assert_predicate FactoryBot.build(:event, slug: "my-event-2024"), :valid?
  end

  # Digital programme link

  test "accepts a blank digital programme link" do
    [ nil, "" ].each do |blank|
      event = FactoryBot.build(:event, digital_programme_url: blank)
      assert event.valid?, "Expected #{blank.inspect} to be allowed"
    end
  end

  test "accepts an http or https digital programme link" do
    [ "https://example.com/programme.pdf", "http://example.com/programme" ].each do |url|
      event = FactoryBot.build(:event, digital_programme_url: url)
      assert event.valid?, "Expected #{url.inspect} to be valid"
    end
  end

  # It becomes a QR code, where a scheme-less string opens nothing, and a public
  # anchor, where "javascript:" would run.
  test "rejects a digital programme link with no scheme or a dangerous one" do
    [ "example.com/programme", "www.example.com", "javascript:alert(1)", "ftp://example.com",
      "https://",
      # Passes a check anchored with \A alone: a newline smuggles a second scheme.
      "https://ok.example.com\njavascript:alert(1)" ].each do |url|
      event = FactoryBot.build(:event, digital_programme_url: url)
      assert_not event.valid?, "Expected #{url.inspect} to be invalid"
      assert event.errors[:digital_programme_url].any?, "Expected errors for #{url.inspect}"
    end
  end

  # Company association via company_name virtual field

  test "company_name returns the associated company name" do
    event = FactoryBot.create(:event)
    event.company = companies(:gutter_theatre)
    assert_equal companies(:gutter_theatre).name, event.company_name
  end

  test "company_name returns nil when no company is set" do
    event = FactoryBot.build(:event)
    assert_nil event.company_name
  end

  test "company_name= resolves to an existing company (case-insensitive)" do
    event = FactoryBot.build(:event, company_name: companies(:gutter_theatre).name.upcase)
    event.validate
    assert_equal companies(:gutter_theatre), event.company
  end

  test "company_name= creates a new, unreviewed company when it does not match" do
    event = FactoryBot.build(:event, company_name: "A Brand New Society")
    assert_difference("Company.count", 1) { event.save! }
    assert_equal "A Brand New Society", event.company.name
    assert_not event.company.reviewed, "newly created companies should be unreviewed"
  end

  test "blank company_name= clears the company" do
    event = FactoryBot.create(:event)
    event.company = companies(:gutter_theatre)
    event.company_name = ""
    event.validate
    assert_nil event.company
  end

  test "destroying an event destroys its unreviewed company when it has no other opportunities or events" do
    event = FactoryBot.create(:event, company_name: "Orphan Society")
    company = event.company
    assert_not company.reviewed

    assert_difference("Company.count", -1) { event.destroy }
    assert_raises(ActiveRecord::RecordNotFound) { company.reload }
  end

  test "destroying an event keeps its unreviewed company when shared with another event" do
    event1 = FactoryBot.create(:event, company_name: "Shared Society")
    event2 = FactoryBot.create(:event, company_name: "Shared Society")
    company = event1.company

    assert_no_difference("Company.count") { event1.destroy }
    assert company.reload.persisted?
  end

  test "destroying an event keeps its unreviewed company when shared with an opportunity" do
    event = FactoryBot.create(:event, company_name: "Shared Society")
    Opportunity.create!(title: "T", description: "D", expiry_date: 1.week.from_now, creator_id: 1,
                        company_name: event.company.name, approved: false)
    company = event.company

    assert_no_difference("Company.count") { event.destroy }
    assert company.reload.persisted?
  end

  test "destroying an event keeps a reviewed company" do
    event = FactoryBot.create(:event, company_name: companies(:gutter_theatre).name)
    assert companies(:gutter_theatre).reviewed

    assert_no_difference("Company.count") { event.destroy }
  end

  # The ~3000 archive events have no occurrence rows.
  test "on_today? is true every day of the run when the event has no occurrences" do
    event = FactoryBot.create(:show, start_date: Date.current - 2, end_date: Date.current + 2, is_public: true)

    assert event.on_today?
    assert event.on_today?(Date.current + 1)
    assert_not event.on_today?(Date.current + 3)
  end

  test "on_today? is only true on days the event actually has an occurrence" do
    event = FactoryBot.create(:show, start_date: Date.current, end_date: Date.current + 4, is_public: true)
    FactoryBot.create(:event_occurrence, event: event, starts_at: (Date.current + 2).noon + 7.hours)

    assert event.on_today?(Date.current + 2)
    assert_not event.on_today?(Date.current + 1)
    assert_not event.on_today?
  end

  test "next_occurrence returns the date of the next occurrence" do
    event = FactoryBot.create(:show, start_date: Date.current, end_date: Date.current + 6, is_public: true)
    FactoryBot.create(:event_occurrence, event: event, starts_at: (Date.current + 4).noon + 7.hours)

    assert_equal Date.current + 4, event.next_occurrence
  end

  test "next_occurrence is the start date when the run has not begun and nothing is scheduled" do
    event = FactoryBot.create(:show, start_date: Date.current + 10, end_date: Date.current + 12, is_public: true)

    assert_equal Date.current + 10, event.next_occurrence
  end

  test "next_occurrence is nil once every occurrence has passed" do
    event = FactoryBot.create(:show, start_date: Date.current - 4, end_date: Date.current + 4, is_public: true)
    FactoryBot.create(:event_occurrence, event: event, starts_at: (Date.current - 2).noon + 7.hours)

    assert_nil event.next_occurrence
  end

  test "next_occurrence is nil once the run has ended" do
    event = FactoryBot.create(:show, start_date: Date.current - 10, end_date: Date.current - 5, is_public: true)

    assert_nil event.next_occurrence
  end

  test "next_occurrence skips the occurrences before the date asked from" do
    event = FactoryBot.create(:show, start_date: Date.current, end_date: Date.current + 6, is_public: true)
    FactoryBot.create(:event_occurrence, event: event, starts_at: (Date.current + 1).noon + 7.hours)
    FactoryBot.create(:event_occurrence, event: event, starts_at: (Date.current + 3).noon + 7.hours)

    assert_equal Date.current + 3, event.next_occurrence(Date.current + 2)
  end
end
