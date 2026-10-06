# An index plus one file per section, so a crawler can re-fetch only the section that changed.
class SitemapsController < ApplicationController
  skip_authorization_check

  # sitemaps.org caps a file at 50,000 URLs.
  MAX_URLS_PER_SECTION = 50_000

  # Section => [entries method, changefreq]. A literal map, not an interpolated send: Brakeman
  # flags that however well it is guarded. changefreq is advisory: Google largely ignores it,
  # Bing and others still read it.
  SECTIONS = {
    "pages" => [ :pages_entries, "monthly" ], "events" => [ :events_entries, "daily" ],
    "news" => [ :news_entries, "weekly" ], "venues" => [ :venues_entries, "monthly" ],
    "members" => [ :members_entries, "monthly" ]
  }.freeze

  def index
    @sections = SECTIONS.keys

    render formats: :xml
  end

  def section
    builder, @change_frequency = SECTIONS[params[:section]]

    head :not_found and return if builder.nil?

    @entries = method(builder).call

    render :section, formats: :xml
  end

  private

  # The hubs, the static pages and every editable-block subpage.
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

  # accessible_by keeps unpublished events out: a sitemap must not advertise a URL that 403s.
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

  # Members are indexed on purpose. Opting out is public_profile, which the guest ability's
  # :view_shows_and_bio rule reads, so an opted-out profile is neither listed nor reachable.
  def members_entries
    capped(User.accessible_by(guest_ability, :view_shows_and_bio)) do |user|
      { loc: user_url(user), lastmod: user.updated_at }
    end
  end

  # Reads in batches and stops at the cap, so a section never loads its whole table.
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
