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
  # Stable token identifying the unfilled members-only-text template so the show
  # page can skip rendering it. The template carries it in a self-documenting HTML
  # comment (`<!-- members-only-template — delete this line… -->`); only this token
  # is the contract, so the human instruction after it can be reworded freely.
  MEMBERS_ONLY_TEMPLATE_MARKER = "<!-- members-only-template"

  # What this type calls its EventOccurrences. Overridden by each subclass; a
  # constant rather than a string typed into each view, so the admin form, the
  # public page and the box office screen cannot drift on the word.
  OCCURRENCE_LABEL = "Date".freeze

  # Whether an occurrence of this type is a performance of the event, or merely a
  # span of time it is open for. Season overrides it: publishing its opening
  # hours as events of their own claims the theatre is staging a show for every
  # day the box office is open.
  OCCURRENCES_ARE_PERFORMANCES = true

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
  validates :age_guidance, length: { maximum: 255 }
  # Blank is normal; a running time of zero or of a day and a half is a typo.
  validates :duration_minutes, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: 1440
  }, allow_nil: true
  validates :doors_open_minutes_before, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: 240
  }, allow_nil: true
  # greater_than 0, not >= 0, because a decimal column casts unreadable input to
  # zero without complaint -- "£0 booking fee on the door" published from a typo.
  # A fee of nothing is no fee: leave it blank.
  validates :booking_fee, numericality: { greater_than: 0 }, allow_nil: true
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

  # NOT :all_blank. The nested form's access_flags check_boxes always post a
  # leading "" from their hidden field, so an untouched blank row is never
  # all-blank -- it was saved, failed validation, and took the whole event update
  # down with "starts at must not be blank".
  # The rule exists to drop the empty "Add a performance" template row, which
  # carries no id. An existing record must NOT be rejected for a missing
  # starts_at: a pretix-synced row renders its times as text rather than inputs
  # (they are pretix's to set), so an edit to its flags, note or cancelled state
  # posts no starts_at at all -- and on the blanket rule it saved, redirected and
  # silently discarded the change.
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

  # Artwork somebody actually uploaded, as opposed to an attachment of any kind.
  # The two are not the same: fetch_image *attaches* a generated placeholder, so
  # every archive event whose page has ever been rendered carries an attachment
  # whether or not it has a poster. What separates them is the filename --
  # ActiveStorageHelper stores its placeholders under a reserved prefix, which
  # is also how get_file_attached_hint tells them apart. sanitize_sql_like
  # escapes the underscores in that prefix, which LIKE would otherwise read as
  # single-character wildcards.
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

  # The events Pretix::SyncPerformancesJob keeps in step with their series.
  #
  # Bounded by the run's end rather than its start: a show still selling for
  # tonight is due, an archive row is not. Both dates are required above, so a
  # ticked event always has one.
  scope :pretix_performance_sync_due, -> {
    where(pretix_sync_performances: true).where(end_date: Date.current..)
  }

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
    prices = Array(values).map { |value| value.is_a?(TicketPrice) ? value : TicketPrice.from_h(value) }

    # Held from assignment because the cast destroys the evidence: "ten" is
    # already 0 by the time the column is read back, and 0 reads as Free.
    @invalid_ticket_prices = prices.reject(&:valid?)

    super(prices.map(&:to_h))
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

  # "2 hours 15 minutes". distance_of_time_in_words rounds this to "about 2
  # hours", which throws away the quarter hour somebody is planning their evening
  # around.
  def duration_in_words
    return nil if duration_minutes.blank?

    hours, minutes = duration_minutes.divmod(60)
    parts = []
    parts << "#{hours} #{'hour'.pluralize(hours)}" if hours.positive?
    parts << "#{minutes} #{'minute'.pluralize(minutes)}" if minutes.positive?

    parts.join(" ")
  end

  # The running time as schema.org wants it: "PT2H15M". Nil when nobody has said
  # how long the thing runs for, which is most of the archive.
  def iso8601_duration
    return nil if duration_minutes.blank?

    hours, minutes = duration_minutes.divmod(60)

    "PT#{"#{hours}H" if hours.positive?}#{"#{minutes}M" if minutes.positive?}"
  end

  # What this event calls its EventOccurrences. Resolved through the STI
  # ancestry, so Show gets "Performance" and everything unspecified gets "Date".
  def occurrence_label
    self.class::OCCURRENCE_LABEL
  end

  def occurrences_are_performances?
    self.class::OCCURRENCES_ARE_PERFORMANCES
  end

  # The facts that hold for the whole run rather than for one night: running
  # time, doors, age guidance, the booking fee. Doors moved off the per-night
  # rows when those collapsed into ranges -- it is the same offset every night.
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

  ##
  # TicketPrice validates itself, but nothing was running those validations --
  # there is no association here to cascade through, and the form's min="0" is
  # client-side only. Without this a negative, an unknown band or a typo saves
  # clean and is published.
  ##
  def ticket_prices_are_valid
    invalid = Array(@invalid_ticket_prices) + ticket_prices.reject(&:valid?)

    invalid.flat_map { |price| price.errors.full_messages }.uniq.each do |message|
      errors.add(:ticket_prices, message.downcase_first)
    end
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

    return clear_derived_price if prices.empty?

    self.price = price_string_for(prices)
  end

  def price_string_for(prices)
    prices.all?(&:free?) ? "Free" : prices.map(&:to_price_string).join(" / ")
  end

  ##
  # Only when it is still the string the previous bands wrote. Anything typed by
  # hand ("Pay what you can") belongs to whoever typed it, and a Show validates
  # the presence of price -- so clearing a derived one correctly fails the save
  # and asks them what the price is now.
  ##
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
