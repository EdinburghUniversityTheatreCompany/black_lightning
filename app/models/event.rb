##
# Probably the most important model in the app.
#
# Note that urls are generated to include the slug rather than the id of an event.
# Therefore, all lookups must be done as follows:
#  @event = Event.find_by_slug(params[:id])
#

# == Schema Information
#
# Table name: events
# Database name: primary
#
#  id                        :integer          not null, primary key
#  age_guidance              :string(255)
#  author                    :string(255)
#  booking_fee               :decimal(8, 2)
#  content_warnings          :text(16777215)
#  digital_programme_url     :string(255)
#  doors_open_minutes_before :integer
#  duration_minutes          :integer
#  end_date                  :date
#  image_content_type        :string(255)
#  image_file_name           :string(255)
#  image_file_size           :integer
#  image_updated_at          :datetime
#  is_public                 :boolean
#  maintenance_debt_amount   :integer
#  maintenance_debt_start    :date
#  members_only_text         :text(16777215)
#  name                      :string(255)
#  pretix_shown              :boolean
#  pretix_slug_override      :string(255)
#  pretix_sync_error         :string(255)
#  pretix_sync_performances  :boolean
#  pretix_synced_at          :datetime
#  pretix_view               :string(255)
#  price                     :string(255)
#  publicity_text            :text(16777215)
#  slug                      :string(255)
#  spark_seat_slug           :string(255)
#  staffing_debt_amount      :integer
#  staffing_debt_start       :date
#  start_date                :date
#  tagline                   :string(255)
#  ticket_prices             :json
#  type                      :string(255)
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  company_id                :bigint
#  proposal_id               :integer
#  season_id                 :integer
#  venue_id                  :integer
#  xts_id                    :integer
#
# Indexes
#
#  index_events_on_author                  (author)
#  index_events_on_company_id              (company_id)
#  index_events_on_date_range              (start_date,end_date)
#  index_events_on_end_date_and_is_public  (end_date,is_public)
#  index_events_on_proposal_id             (proposal_id)
#  index_events_on_season_id               (season_id)
#  index_events_on_venue_id                (venue_id)
#
# Foreign Keys
#
#  fk_rails_...  (company_id => companies.id)
#  fk_rails_...  (proposal_id => admin_proposals_proposals.id)
#
class Event < ApplicationRecord
  # Marks the unfilled members-only template so the show page can skip it. Only
  # this token is the contract; the instruction after it can be reworded.
  MEMBERS_ONLY_TEMPLATE_MARKER = "<!-- members-only-template"

  # What this type calls its EventOccurrences; each subclass overrides it.
  OCCURRENCE_LABEL = "Date".freeze

  # Season overrides this: publishing its opening hours as performances would
  # claim a show on every day the box office is open.
  OCCURRENCES_ARE_PERFORMANCES = true

  # The schema.org type of the run and its performance nodes.
  SCHEMA_TYPE = "TheaterEvent".freeze

  validates :name, :tagline, :slug, length: { maximum: 255 }
  validates :publicity_text, length: { maximum: 16777215 }
  validates :image_file_name, :image_content_type, :author, :type, :price, :spark_seat_slug, length: { maximum: 255 }
  validates :members_only_text, length: { maximum: 16777215 }
  validates :pretix_slug_override, :pretix_view, length: { maximum: 255 }
  validates :content_warnings, length: { maximum: 16777215 }
  validates :digital_programme_url, :age_guidance, length: { maximum: 255 }
  # The upper bounds are fat-finger backstops.
  validates :duration_minutes, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: 1440
  }, allow_nil: true
  validates :doors_open_minutes_before, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: 240
  }, allow_nil: true
  # Not >= 0: a decimal column casts unreadable input to 0, which would publish
  # "£0 booking fee on the door".
  validates :booking_fee, numericality: { greater_than: 0 }, allow_nil: true
  # A public anchor and a box office QR code: a scheme-less value breaks both and
  # "javascript:" would run. \z and \S, because \A alone lets a newline smuggle a
  # second scheme into the href.
  validates :digital_programme_url, format: {
    with: %r{\Ahttps?://\S+\z}i, message: "must be a full http:// or https:// link"
  }, allow_blank: true
  include TimeHelper
  include ApplicationHelper
  include AttachmentItem
  include VideoLinkItem
  include MdHelper
  include DebtManagement
  include Sluggable
  include TeamMemberOrdering

  # Resolved to a Company (created if needed) by assign_company_from_name.
  attr_writer :company_name

  has_paper_trail
  resourcify

  AUTHOR_NAME_LIST_CACHE_KEY = "Event/author_name_list".freeze

  # Use the format slug for urls. e.g. /events/myshow
  def to_param
    slug
  end

  # Validations #
  validates :name, :slug, :publicity_text, :members_only_text, :start_date, :end_date, presence: true
  validates :slug, uniqueness: { case_sensitive: false }
  validate :end_date_after_start_date
  validate :ticket_prices_are_valid

  # Relationships #

  belongs_to :company, optional: true
  belongs_to :proposal, class_name: "Admin::Proposals::Proposal", optional: true

  has_many :event_occurrences, dependent: :destroy
  has_many :team_members, class_name: "::TeamMember", as: :teamwork, dependent: :destroy
  has_many :users, through: :team_members
  has_many :pictures, as: :gallery, dependent: :restrict_with_error
  has_many :questionnaires, class_name: "Admin::Questionnaires::Questionnaire", dependent: :restrict_with_error
  has_many :reviews, dependent: :restrict_with_error

  belongs_to :venue
  belongs_to :season, optional: true

  has_and_belongs_to_many :event_tags, optional: true

  # Not :all_blank: the access_flags check_boxes post a leading "", so the empty
  # template row is never all-blank. Only a row with no id is dropped, because a
  # pretix-synced row posts no starts_at (its times are text, not inputs) and
  # rejecting it would silently discard an edit to its flags or note.
  accepts_nested_attributes_for :event_occurrences, allow_destroy: true,
                                reject_if: ->(attributes) {
                                  attributes["id"].blank? && attributes["starts_at"].blank?
                                }
  accepts_nested_attributes_for :team_members, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :pictures, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :reviews, reject_if: :all_blank, allow_destroy: true

  # ActiveStorage #
  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif webp]

  # Normalizatios
  normalizes :name, :tagline, :slug, :author, :price, with: ->(value) { value&.strip }

  # Scopes #

  scope :current, -> { where([ "end_date >= ? AND is_public = ?", Date.current, true ]) }
  scope :future, -> { where([ "end_date >= ?", Date.current ]) }
  scope :this_academic_year, -> { where("end_date >= ?", ApplicationController.helpers.start_of_year).where("start_date < ?", ApplicationController.helpers.next_year_start) }

  # Artwork somebody uploaded. fetch_image attaches a placeholder to any event
  # whose page was rendered, so filter on the placeholder filename prefix;
  # sanitize_sql_like escapes its underscores, which LIKE reads as wildcards.
  scope :with_uploaded_image, -> {
    joins(image_attachment: :blob)
      .where.not("active_storage_blobs.filename LIKE ?",
                 "#{sanitize_sql_like("#{ActiveStorageHelper::PREFIX}/")}%")
  }

  def this_academic_year?
    end_date >= ApplicationController.helpers.start_of_year && start_date < ApplicationController.helpers.next_year_start
  end

  # ONLY LOOKS AT DAY AND MONTH! NOT AT YEAR.
  # Excludes shows that go into a new year (imps, candlewasters, the old ones we only know the year off, etc) because complicated logic and it wasn't very relevant.
  scope :on_date, ->(date) { where("(MONTH(start_date) < :month OR (MONTH(start_date) = :month AND DAY(start_date) <= :day)) AND (MONTH(end_date) > :month OR (MONTH(end_date) = :month AND DAY(END_DATE) >= :day))", { day: date.day, month: date.month }) }

  # Events are generally ordered with the most recent/upcoming ones first.
  default_scope -> { order("end_date DESC") }

  # Callbacks
  slug_from :name
  before_validation :assign_company_from_name
  after_initialize :set_default_members_only_text
  before_validation :derive_price_from_ticket_prices, if: :will_save_change_to_ticket_prices?
  after_update :recache_author_list_if_changed
  after_destroy :cleanup_orphaned_company

  # Returns the last event to have finished.
  def self.last_event
    reorder("end_date DESC").where([ "end_date < ? AND is_public = ?", Date.current, true ]).first
  end

  # Formats the shows so they can be used in a selection field
  def self.selection_collection
    pluck(:name, :id)
  end

  def company_name
    company&.name
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[author company_id end_date is_public maintenance_debt_start members_only_text name pretix_shown price proposal_id publicity_text season_id slug staffing_debt_start start_date tagline type venue_id]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "attachments", "company", "event_tags", "pictures", "proposal", "questionnaires", "reviews", "roles", "season", "team_members", "users", "venue", "versions", "video_links" ]
  end

  ##
  # Generates a default image for the event. If extra artwork is added, increase the base of the modulo call.
  #
  # NOTE: The first image must have filename 0.png - remember that in modulo 4 (for example), valid numbers are 0,1,2,3 (not 4)!
  ##
  def fetch_image
    number = id.modulo(4)
    image.attach(ApplicationController.helpers.default_image_blob("events/#{number}.png")) unless image.attached?

    image
  end

  ##
  # Returns the url of the slideshow image
  ##
  def thumb_image_url
    Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.slideshow_variant).processed, only_path: true)
  end

  ##
  # Returns the url of the slideshow image
  ##
  def slideshow_image_url
    Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.slideshow_variant).processed, only_path: true)
  end

  ##
  # Generates the frequently used "startdate - enddate" string.
  #
  # The date format used is the :long format, defined in /config/locales/en.yml
  ##
  def date_range(include_year, format = :long)
    time_range_string(start_date, end_date, include_year, format)
  end

  def short_blurb
    tagline.presence || truncate_markdown(publicity_text, 120)
  end

  # Returns the name and author in one string, or just the name if no author is specified.
  def name_and_author
    if author.present? && author.upcase.strip != "NEVER SET"
      "\"#{name}\"#{" by #{author}"}"
    else
      name
    end
  end

  # Returns the date and price in one string, or just the date if no price is specified.
  def date_and_price
    if price.present?
      "#{date_range(false)} - #{price}"
    else
      date_range(false)
    end
  end

  def simultaneous_seasons
    Season.where("start_date <= ? and end_date >= ?", end_date, start_date)
  end

  def possible_proposals
    proposals = Admin::Proposals::Proposal.where(status: :successful)

    if persisted?
      date_range = start_date.advance(years: -1)..start_date

      call_ids = Admin::Proposals::Call.where(submission_deadline: date_range).ids

      proposals = proposals.where(call_id: call_ids)

      # The attached proposal should always be included, even if it does not fall within the range or was not successful.
      proposals = proposals.or(Admin::Proposals::Proposal.where(id: proposal.id)) if proposal.present?
    end

    proposals
  end

  def all_attachments
    answers = Admin::Answer.where(answerable: questionnaires).or(Admin::Answer.where(answerable: proposal))

    attachments.or(Attachment.where(item: answers))
  end

  def set_default_members_only_text
    return if !has_attribute?(:members_only_text) || members_only_text.present?

    editable_block = Admin::EditableBlock.find_by(name: "Event Members-Only Text Default")

    self.members_only_text = editable_block.present? ? editable_block.content : ""
  end

  # True once an author has replaced the default template with real content.
  def members_only_text_customised?
    members_only_text.present? && members_only_text.exclude?(MEMBERS_ONLY_TEMPLATE_MARKER)
  end

  def as_json(options = {})
    defaults = { methods: [ :thumb_image_url, :slideshow_image_url ], include: [ :venue, { pictures: { methods: [ :thumb_url, :display_url ] } }, team_members: { methods: [ :user_name ] } ] }

    options = merge_hash(defaults, options)

    super(options)
  end

  # Bounded by the run's end: a show selling for tonight is due, an archive row
  # is not.
  scope :pretix_performance_sync_due, -> {
    where(pretix_sync_performances: true).where(end_date: Date.current..)
  }

  def pretix_slug
    pretix_slug_override.presence || slug
  end

  # The priced bands, dearest first, stored as hashes in a JSON column.
  # ticket_prices_attributes= lets fields_for edit it as if it were an association.
  def ticket_prices
    Array(super).map { |attributes| TicketPrice.from_h(attributes) }
                .sort_by { |price| -(price.amount || 0) }
  end

  def ticket_prices=(values)
    prices = Array(values).map { |value| value.is_a?(TicketPrice) ? value : TicketPrice.from_h(value) }

    # Held from assignment: the cast turns "ten" into 0, and 0 reads as Free.
    @invalid_ticket_prices = prices.reject(&:valid?)

    super(prices.map(&:to_h))
  end

  # A row with no amount is the blank template row the form always posts.
  def ticket_prices_attributes=(attributes)
    rows = attributes.respond_to?(:values) ? attributes.values : Array(attributes)

    self.ticket_prices = rows.map { |row| row.to_h.with_indifferent_access }
                             .reject { |row| ActiveModel::Type::Boolean.new.cast(row[:_destroy]) || row[:amount].blank? }
  end

  # "2 hours 15 minutes"; distance_of_time_in_words would round off the quarter hour.
  def duration_in_words
    return nil if duration_minutes.blank?

    hours, minutes = duration_minutes.divmod(60)
    parts = []
    parts << "#{hours} #{'hour'.pluralize(hours)}" if hours.positive?
    parts << "#{minutes} #{'minute'.pluralize(minutes)}" if minutes.positive?

    parts.join(" ")
  end

  # "PT2H15M", as schema.org wants it.
  def iso8601_duration
    return nil if duration_minutes.blank?

    hours, minutes = duration_minutes.divmod(60)

    "PT#{"#{hours}H" if hours.positive?}#{"#{minutes}M" if minutes.positive?}"
  end

  def occurrence_label
    self.class::OCCURRENCE_LABEL
  end

  def occurrences_are_performances?
    self.class::OCCURRENCES_ARE_PERFORMANCES
  end

  def schema_type
    self.class::SCHEMA_TYPE
  end

  # The facts that hold for every night of the run.
  def schedule_details
    details = []
    details << "running time #{duration_in_words}, including any interval" if duration_minutes.present?
    details << "doors open #{doors_open_minutes_before} minutes before" if doors_open_minutes_before.present?
    details << "age guidance #{age_guidance}" if age_guidance.present?

    if booking_fee.present?
      details << "#{TicketPrice.new(amount: booking_fee).formatted_amount} booking fee on the door"
    end

    details
  end

  # No occurrences means every day of the run: the ~3000 archive rows, and any
  # event whose times are not filled in yet.
  def on_today?(date = Date.current)
    return false if start_date.nil? || end_date.nil?
    return false unless (start_date..end_date).cover?(date)
    return true if event_occurrences.empty?

    event_occurrences.any? { |occurrence| occurrence.on_date == date }
  end

  # The next date it plays on or after +from+, or nil. Works in memory, not by
  # query: the box office display asks this of every event in its pool.
  def next_occurrence(from = Date.current)
    return nil if start_date.nil? || end_date.nil?

    from = [ from, start_date ].max
    return nil if from > end_date
    return from if event_occurrences.empty?

    event_occurrences.filter_map(&:on_date).select { |date| date >= from }.min
  end

  # Returns a list of the all authors for every event.
  def self.author_name_list
    Rails.cache.fetch(AUTHOR_NAME_LIST_CACHE_KEY, expires_in: 12.hours) do
      Event.where.not(author: nil).pluck(:author).uniq.sort
    end
  end

  private

  def recache_author_list_if_changed
    if saved_change_to_author?
      # Clear the cache for the author_name_list so it regenerates.
      Rails.cache.delete(AUTHOR_NAME_LIST_CACHE_KEY)
    end
  end

  def end_date_after_start_date
    return unless start_date.present? && end_date.present?

    if end_date < start_date
      errors.add(:end_date, "must be after or equal to start date")
    end
  end

  def assign_company_from_name
    self.company = Company.find_or_build_by_name(@company_name) unless @company_name.nil?
  end

  # A JSON column has no association to cascade the bands' validations through.
  def ticket_prices_are_valid
    invalid = Array(@invalid_ticket_prices) + ticket_prices.reject(&:valid?)

    invalid.flat_map { |price| price.errors.full_messages }.uniq.each do |message|
      errors.add(:ticket_prices, message.downcase_first)
    end
  end

  # price stays the display string every view renders, regenerated whenever the
  # bands change. The backfill writes with update_columns and skips this, so the
  # archive renders as before.
  def derive_price_from_ticket_prices
    prices = ticket_prices

    return clear_derived_price if prices.empty?

    self.price = price_string_for(prices)
  end

  def price_string_for(prices)
    prices.all?(&:free?) ? "Free" : prices.map(&:to_price_string).join(" / ")
  end

  # Only the string the previous bands wrote: a hand-typed price belongs to whoever
  # typed it. A Show validates price presence, so clearing a derived one fails the
  # save and asks for the new price.
  def clear_derived_price
    previous = Array(ticket_prices_in_database).map { |attributes| TicketPrice.from_h(attributes) }

    return if previous.empty?
    return unless price == price_string_for(previous)

    self.price = nil
  end

  def cleanup_orphaned_company
    return unless company.present?

    company.destroy if !company.reviewed? && company.opportunities.none? && company.events.none?
  end
end
