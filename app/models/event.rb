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
#  id                     :integer          not null, primary key
#  name                   :string(255)
#  tagline                :string(255)
#  slug                   :string(255)
#  description            :text(65535)
#  xts_id                 :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  is_public              :boolean
#  image_file_name        :string(255)
#  image_content_type     :string(255)
#  image_file_size        :integer
#  image_updated_at       :datetime
#  start_date             :date
#  end_date               :date
#  venue_id               :integer
#  season_id              :integer
#  author                 :string(255)
#  type                   :string(255)
#  price                  :string(255)
#  spark_seat_slug        :string(255)
#  maintenance_debt_start :date
#  staffing_debt_start    :date
#

class Event < ApplicationRecord
  include TimeHelper
  include ApplicationHelper

  resourcify

  # Use the format slug for urls. e.g. /events/myshow
  def to_param
    slug
  end

  # Validations #

  validates :name, :slug, :description, :start_date, :end_date, presence: true

  # Relationships #

  belongs_to :proposal, class_name: 'Admin::Proposals::Proposal', optional: true

  has_many :team_members, class_name: '::TeamMember', as: :teamwork, dependent: :restrict_with_error
  has_many :users, through: :team_members
  has_many :pictures, as: :gallery, dependent: :restrict_with_error

  belongs_to :venue
  belongs_to :season, optional: true

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

  def as_json(options = {})
    defaults = {
      include: [
        :venue
      ]
    }

    options = merge_hash(defaults, options)

    super(options)
  end
end
