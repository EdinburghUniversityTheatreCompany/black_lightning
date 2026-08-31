##
# An index plus one file per section rather than a single file: the sections grow at very
# different rates, so a crawler can re-fetch only the one that changed. Without this the only
# route into the archive is 164 pages of pagination.
##
class SitemapsController < ApplicationController
  skip_authorization_check

  # sitemaps.org caps a single file at 50,000 URLs. No section is near that, but a cap that is
  # never checked is a cap that silently breaks the day it is passed.
  MAX_URLS_PER_SECTION = 50_000

  # A literal map rather than a name interpolated into send, which Brakeman flags as a dangerous
  # send however well the allow-list guards it.
  SECTION_BUILDERS = {
    "pages" => :pages_entries, "events" => :events_entries, "news" => :news_entries,
    "venues" => :venues_entries, "members" => :members_entries
  }.freeze

  SECTIONS = SECTION_BUILDERS.keys.freeze

  # How often each section is worth re-crawling. Advisory -- Google largely ignores changefreq,
  # but Bing and others still read it.
  CHANGE_FREQUENCIES = {
    "pages" => "monthly", "events" => "daily", "news" => "weekly",
    "venues" => "monthly", "members" => "monthly"
  }.freeze

  def index
    @sections = SECTIONS

    render formats: :xml
  end

  def section
    @section = params[:section]
    builder = SECTION_BUILDERS[@section]

    head :not_found and return if builder.nil?

    @entries = method(builder).call
    @change_frequency = CHANGE_FREQUENCIES.fetch(@section)

    render :section, formats: :xml
  end

  private

  # Everything hand-written that is not a record: the hubs, the static pages and every
  # editable-block subpage.
  def pages_entries
    fixed = [
      root_url, events_url, shows_url, workshops_url, seasons_url, news_index_url,
      venues_url, archives_index_url, get_involved_opportunities_url
    ]

    fixed += StaticController::ALLOWED_PAGES.map { |page| static_url(page) }

    entries = fixed.map { |url| { loc: url } }

    entries + capped(Admin::EditableBlock.where(admin_page: false).where.not(url: [ nil, "" ])) do |block|
      { loc: "#{root_url.chomp('/')}/#{block.url}", lastmod: block.updated_at }
    end
  end

  # accessible_by keeps unpublished events out: a sitemap must never advertise a URL that
  # answers 403 to the crawler reading it.
  def events_entries
    capped(Event.accessible_by(guest_ability).where.not(slug: [ nil, "" ])) do |event|
      { loc: polymorphic_url(event), lastmod: event.updated_at }
    end
  end

  def news_entries
    capped(News.accessible_by(guest_ability)) { |item| { loc: news_url(item), lastmod: item.updated_at } }
  end

  def venues_entries
    capped(Venue.accessible_by(guest_ability)) { |venue| { loc: venue_url(venue), lastmod: venue.updated_at } }
  end

  # Members are indexed on purpose. Opting out is public_profile, which is exactly what the
  # guest ability's :view_shows_and_bio rule reads, so an opted-out profile is never listed here
  # and 403s if a crawler reaches it anyway.
  def members_entries
    capped(User.accessible_by(guest_ability, :view_shows_and_bio)) do |user|
      { loc: user_url(user), lastmod: user.updated_at }
    end
  end

  ##
  # Reads a section in batches and stops at the cap, so a sitemap never instantiates the whole
  # table. Members alone run to five figures, and the cap used to be applied after loading all
  # of them.
  ##
  def capped(scope)
    entries = []

    scope.find_each(batch_size: 1000) do |record|
      entries << yield(record)

      break if entries.size >= MAX_URLS_PER_SECTION
    end

    entries
  end

  def guest_ability
    @guest_ability ||= Ability.new(nil)
  end
end
