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
#  id                      :integer          not null, primary key
#  author                  :string(255)
#  booking_fee             :decimal(8, 2)
#  content_warnings        :text(16777215)
#  digital_programme_url   :string(255)
#  end_date                :date
#  image_content_type      :string(255)
#  image_file_name         :string(255)
#  image_file_size         :integer
#  image_updated_at        :datetime
#  is_public               :boolean
#  maintenance_debt_amount :integer
#  maintenance_debt_start  :date
#  members_only_text       :text(16777215)
#  name                    :string(255)
#  pretix_shown            :boolean
#  pretix_slug_override    :string(255)
#  pretix_view             :string(255)
#  price                   :string(255)
#  publicity_text          :text(16777215)
#  slug                    :string(255)
#  spark_seat_slug         :string(255)
#  staffing_debt_amount    :integer
#  staffing_debt_start     :date
#  start_date              :date
#  tagline                 :string(255)
#  ticket_prices           :json
#  type                    :string(255)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  company_id              :bigint
#  proposal_id             :integer
#  season_id               :integer
#  venue_id                :integer
#  xts_id                  :integer
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
  # Stable token identifying the unfilled members-only-text template so the show
  # page can skip rendering it. The template carries it in a self-documenting HTML
  # comment (`<!-- members-only-template — delete this line… -->`); only this token
  # is the contract, so the human instruction after it can be reworded freely.
  MEMBERS_ONLY_TEMPLATE_MARKER = "<!-- members-only-template"

  # What this type calls its EventOccurrences. Overridden by each subclass; a
  # constant rather than a string typed into each view, so the admin form, the
  # public page and the box office screen cannot drift on the word.
  OCCURRENCE_LABEL = "Date".freeze

  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :tagline, length: { maximum: 255 }
  validates :slug, length: { maximum: 255 }
  validates :publicity_text, length: { maximum: 16777215 }
  validates :image_file_name, length: { maximum: 255 }
  validates :image_content_type, length: { maximum: 255 }
  validates :author, length: { maximum: 255 }
  validates :type, length: { maximum: 255 }
  validates :price, length: { maximum: 255 }
  validates :spark_seat_slug, length: { maximum: 255 }
  validates :members_only_text, length: { maximum: 16777215 }
  validates :pretix_slug_override, length: { maximum: 255 }
  validates :pretix_view, length: { maximum: 255 }
  validates :content_warnings, length: { maximum: 16777215 }
  validates :digital_programme_url, length: { maximum: 255 }
  # A scheme is required rather than merely encouraged: this value is rendered
  # as an anchor on the public page and encoded straight into a QR code on the
  # box office screen, and a bare "bedlamtheatre.co.uk/programme" resolves as a
  # relative path in the first case and as nothing at all in the second. Only
  # http(s), so a "javascript:" paste cannot become a link on a public page.
  #
  # Anchored at BOTH ends, and no whitespace anywhere: Ruby's \A alone still
  # admits a newline and whatever follows it, which is how a scheme that passed
  # the check smuggles one that did not into an href.
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

  # +company_name+ is a virtual field resolved to a Company (created if needed) by a before_validation hook.
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

  accepts_nested_attributes_for :event_occurrences, reject_if: :all_blank, allow_destroy: true
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

  def this_academic_year?
    end_date >= ApplicationController.helpers.start_of_year && start_date < ApplicationController.helpers.next_year_start
  end

  # ONLY LOOKS AT DAY AND MONTH! NOT AT YEAR.
  # Excludes shows that go into a new year (imps, candlewasters, the old ones we only know the year off, etc) because complicated logic and it wasn't very relevant.
  scope :on_date, ->(date) { where("(MONTH(start_date) < :month OR (MONTH(start_date) = :month AND DAY(start_date) <= :day)) AND (MONTH(end_date) > :month OR (MONTH(end_date) = :month AND DAY(END_DATE) >= :day))", { day: date.day, month: date.month }) }

  # Events are generally ordered with the most recent/upcoming ones first.
  default_scope -> { order("end_date DESC") }

  # Callbacks
  before_validation :generate_slug_from_name, :assign_company_from_name
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

  def pretix_slug
    pretix_slug_override.presence || slug
  end

  ##
  # The priced bands of this event's tickets, dearest first.
  #
  # Stored as an array of plain hashes in the ticket_prices JSON column. Defining
  # <name>_attributes= below is what makes fields_for treat this as if it were an
  # association, so the existing nested-form UI edits it with no new JavaScript.
  ##
  def ticket_prices
    Array(super).map { |attributes| TicketPrice.from_h(attributes) }
                .sort_by { |price| -(price.amount || 0) }
  end

  def ticket_prices=(values)
    super(Array(values).map { |value| value.is_a?(TicketPrice) ? value : TicketPrice.from_h(value) }
                       .map(&:to_h))
  end

  ##
  # The nested-form params shape: a hash of index => attributes, each of which may
  # carry _destroy. A row with no amount is the blank one the form's template
  # always posts, and storing it would mean a band with no price.
  ##
  def ticket_prices_attributes=(attributes)
    rows = attributes.respond_to?(:values) ? attributes.values : Array(attributes)

    self.ticket_prices = rows.reject { |row| destroy_flagged?(row) || row_amount(row).blank? }
  end

  # What this event calls its EventOccurrences. Resolved through the STI
  # ancestry, so Show gets "Performance" and everything unspecified gets "Date".
  def occurrence_label
    self.class::OCCURRENCE_LABEL
  end

  ##
  # An event with NO occurrences plays every day of its run. That is not a
  # placeholder: it is every one of the ~3000 archive rows, plus any event whose
  # producer has not filled the times in yet, and it is exactly the behaviour
  # the retired performance_weekdays column gave when left blank.
  ##
  def on_today?(date = Date.current)
    return false if start_date.nil? || end_date.nil?
    return false unless (start_date..end_date).cover?(date)
    return true if event_occurrences.empty?

    event_occurrences.any? { |occurrence| occurrence.on_date == date }
  end

  # The next date this event actually plays, on or after +from+; nil if it never
  # plays again.
  def next_occurrence(from = Date.current)
    return nil if start_date.nil? || end_date.nil?

    from = [ from, start_date ].max
    return nil if from > end_date
    return from if event_occurrences.empty?

    next_occurrence_at(from)&.on_date
  end

  # The occurrence record itself, so a caller can print a curtain time. Loaded
  # from the association in memory rather than queried, because the box office
  # display asks every event in the pool three of these questions in a row.
  def next_occurrence_at(from = Date.current)
    event_occurrences.select { |occurrence| occurrence.on_date && occurrence.on_date >= from }
                     .min_by(&:starts_at)
  end

  # Returns a list of the all authors for every event.
  def self.author_name_list
    Rails.cache.fetch(AUTHOR_NAME_LIST_CACHE_KEY, expires_in: 12.hours) do
      Event.where.not(author: nil).pluck(:author).uniq.sort
    end
  end

  private

  def generate_slug_from_name
    return unless name.present?

    # Only generate slug if it's blank or if the name changed
    should_generate = slug.blank? || name_changed?

    # If we have an existing slug and the name didn't change, don't modify
    return if slug.present? && !name_changed?

    base_slug = name.to_url

    # If name changed, only update if current slug looks auto-generated from old name
    if name_changed? && slug.present?
      old_name = name_was&.to_url
      # For new records name_was is nil, so treat any pre-set slug as manually set
      return if old_name.nil?
      # Only update if the current slug matches what would have been auto-generated from the old name
      # This indicates it was auto-generated, not manually set
      unless slug == old_name || slug.start_with?("#{old_name}-")
        return # Slug was manually set, don't change it
      end
    end

    # Find a unique slug by appending numbers if needed
    candidate_slug = base_slug
    counter = 1

    while Event.where.not(id: id).where("LOWER(slug) = ?", candidate_slug.downcase).exists?
      candidate_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = candidate_slug
  end

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
    return if @company_name.nil?

    self.company = @company_name.present? ? Company.find_or_build_by_name(@company_name) : nil
  end

  def destroy_flagged?(row)
    ActiveModel::Type::Boolean.new.cast(row["_destroy"] || row[:_destroy])
  end

  def row_amount(row)
    row["amount"] || row[:amount]
  end

  ##
  # price stays the free-text string every existing view renders; the structured
  # bands regenerate it whenever they change, so the two cannot drift. The
  # backfill deliberately does NOT go through here -- it writes ticket_prices with
  # update_columns, leaving all ~3000 archive rows rendering byte-identically.
  ##
  def derive_price_from_ticket_prices
    prices = ticket_prices

    return if prices.empty?

    self.price = prices.all?(&:free?) ? "Free" : prices.map(&:to_price_string).join(" / ")
  end

  def cleanup_orphaned_company
    return unless company.present?

    company.destroy if !company.reviewed? && company.opportunities.none? && company.events.none?
  end
end
