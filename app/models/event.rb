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

class Event < ApplicationRecord
  include TimeHelper
  include ApplicationHelper
  include AttachmentItem
  include VideoLinkItem
  include MdHelper

  has_paper_trail limit: 6
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

  belongs_to :proposal, class_name: "Admin::Proposals::Proposal", optional: true

  has_many :team_members, class_name: "::TeamMember", as: :teamwork, dependent: :destroy
  has_many :users, through: :team_members
  has_many :pictures, as: :gallery, dependent: :restrict_with_error
  has_many :questionnaires, class_name: "Admin::Questionnaires::Questionnaire", dependent: :restrict_with_error
  has_many :reviews, dependent: :restrict_with_error

  belongs_to :venue
  belongs_to :season, optional: true

  has_and_belongs_to_many :event_tags, optional: true

  accepts_nested_attributes_for :team_members, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :pictures, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :reviews, reject_if: :all_blank, allow_destroy: true

  # ActiveStorage #
  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif]

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
  before_validation :generate_slug_from_name
  after_initialize :set_default_members_only_text
  after_update :recache_author_list_if_changed

  # Returns the last event to have finished.
  def self.last_event
    reorder("end_date DESC").where([ "end_date < ? AND is_public = ?", Date.current, true ]).first
  end

  # Formats the shows so they can be used in a selection field
  def self.selection_collection
    pluck(:name, :id)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[author end_date is_public maintenance_debt_start members_only_text name pretix_shown price proposal_id publicity_text season_id slug staffing_debt_start start_date tagline type venue_id]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "attachments", "event_tags", "pictures", "proposal", "questionnaires", "reviews", "roles", "season", "team_members", "users", "venue", "versions", "video_links" ]
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
    (tagline.presence || truncate_markdown(publicity_text, 120)).html_safe
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

  def as_json(options = {})
    defaults = { methods: [ :thumb_image_url, :slideshow_image_url ], include: [ :venue, { pictures: { methods: [ :thumb_url, :display_url ] } }, team_members: { methods: [ :user_name ] } ] }

    options = merge_hash(defaults, options)

    super(options)
  end

  def pretix_slug
    pretix_slug_override.presence || slug
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
end
