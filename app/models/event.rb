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
# *publicity_text*::         <tt>text(65535)</tt>
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
  include MdHelper

  resourcify

  # Use the format slug for urls. e.g. /events/myshow
  def to_param
    slug
  end

  # Validations #
  validates :name, :slug, :publicity_text, :members_only_text, :start_date, :end_date, presence: true

  # Relationships #

  belongs_to :proposal, class_name: 'Admin::Proposals::Proposal', optional: true

  has_many :team_members, class_name: '::TeamMember', as: :teamwork, dependent: :restrict_with_error
  has_many :users, through: :team_members
  has_many :pictures, as: :gallery, dependent: :restrict_with_error
  has_many :questionnaires, class_name: 'Admin::Questionnaires::Questionnaire', dependent: :restrict_with_error

  belongs_to :venue
  belongs_to :season, optional: true

  has_and_belongs_to_many :event_tags, optional: true

  accepts_nested_attributes_for :team_members, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :pictures, reject_if: :all_blank, allow_destroy: true

  # ActiveStorage #
  has_one_attached :image

  validates :image, content_type: %i[png jpg jpeg gif]

  # Scopes #

  scope :current, -> { where(['end_date >= ? AND is_public = ?', Date.current, true]) }
  scope :future, -> { where(['end_date >= ?', Date.current]) }
  scope :this_year, -> { where('end_date >= ?', ApplicationController.helpers.start_of_year).where('start_date < ?', ApplicationController.helpers.next_year_start) }

  # Events are generally ordered with the most recent/upcoming ones first.
  default_scope -> { order('end_date DESC') }

  # Callbacks
  after_initialize :set_default_members_only_text

  # Returns the last event to have finished.
  def self.last_event
    return reorder('end_date DESC').where(['end_date < ? AND is_public = ?', Date.current, true]).first
  end

  # Formats the shows so they can be used in a selection field
  def self.selection_collection
    return pluck(:name, :id)
  end

  ##
  # Generates a default image for the event. If extra artwork is added, increase the base of the modulo call.
  #
  # NOTE: The first image must have filename 0.png - remember that in modulo 4 (for example), valid numbers are 0,1,2,3 (not 4)!
  ##
  def fetch_image
    number = id.modulo(4)
    image.attach(ApplicationController.helpers.default_image_blob("events/#{number}.png")) unless image.attached? 

    return image
  end

  ##
  # Returns the url of the slideshow image
  ##
  def thumb_image_url
    return Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.slideshow_variant).processed, only_path: true)
  end

  ##
  # Returns the url of the slideshow image
  ##
  def slideshow_image_url
    return Rails.application.routes.url_helpers.rails_representation_url(fetch_image.variant(ApplicationController.helpers.slideshow_variant).processed, only_path: true)
  end

  ##
  # Generates the frequently used "startdate - enddate" string.
  #
  # The date format used is the :long format, defined in /config/locales/en.yml
  ##
  def date_range(include_year, format = :long)
    return time_range_string(start_date, end_date, include_year, format)
  end

  def short_blurb
    (tagline.presence || truncate_markdown(publicity_text, 120)).html_safe
  end

  def simultaneous_seasons
    return Season.where('start_date <= ? and end_date >= ?', end_date, start_date)
  end

  def possible_proposals
    proposals = Admin::Proposals::Proposal.where(successful: true)

    if persisted?
      date_range = start_date.advance(years: -1)..start_date

      call_ids = Admin::Proposals::Call.where(submission_deadline: date_range).ids

      proposals = proposals.where(call_id: call_ids)

      # The attached proposal should always be included, even if it does not fall within the range or was not successful.
      proposals = proposals.or(Admin::Proposals::Proposal.where(id: proposal.id)) if proposal.present?
    end

    return proposals
  end

  def all_attachments
    answers = Admin::Answer.where(answerable: questionnaires).or(Admin::Answer.where(answerable: proposal))

    return attachments.or(Attachment.where(item: answers))
  end

  def set_default_members_only_text
    return if members_only_text.present?

    editable_block = Admin::EditableBlock.find_by(name: 'Event Members-Only Text Default')

    self.members_only_text = editable_block.present? ? editable_block.content : ''
  end

  def as_json(options = {})
    defaults = { methods: [:thumb_image_url, :slideshow_image_url], include: [:venue, { pictures: { methods: [:thumb_url, :display_url] } }, team_members: { methods: [:user_name] }] }

    options = merge_hash(defaults, options)

    super(options)
  end

  # Returns a hash with base permitted params to prevent accidentally omitting one.
  def self.base_permitted_params
    return [
      :publicity_text, :members_only_text, :name, :slug, :tagline,
      :author, :venue, :venue_id, :season, :season_id,
      :xts_id, :is_public, :image, :proposal, :proposal_id,
      :start_date, :end_date, :price, :spark_seat_slug, event_tag_ids: [],
      pictures_attributes: [:id, :_destroy, :description, :image],
      team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal],
      attachments_attributes: [:id, :_destroy, :name, :file, :access_level, attachment_tag_ids: []]
    ]
  end
end
