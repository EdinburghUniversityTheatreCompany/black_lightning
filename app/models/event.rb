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

  has_many :team_members, class_name: '::TeamMember', as: :teamwork, dependent: :destroy
  has_many :users, through: :team_members
  has_many :pictures, as: :gallery, dependent: :destroy

  belongs_to :venue, optional: true
  belongs_to :season, optional: true

  accepts_nested_attributes_for :team_members, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :pictures, reject_if: :all_blank, allow_destroy: true

  # Paperclip #
  has_attached_file :image,
                    styles: { medium: '576x300#', thumb: '192x100#', slideshow: '960x500#' },
                    convert_options: { medium: '-strip', thumb: '-quality 75 -strip' },
                    default_url: :default_image

  validates_attachment :image, content_type: { content_type: ["image/jpg", "image/jpeg", "image/png", "image/gif"] }

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
  def default_image
    number = id.modulo(4)
    return "/images/generic_shows/:style/#{number}.png"
  end

  ##
  # Returns the url of the slideshow image
  ##
  def thumb_image
    return image.url(:thumb)
  end

  ##
  # Returns the url of the slideshow image
  ##
  def slideshow_image
    return image.url(:slideshow)
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
