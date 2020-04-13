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

class Event < ActiveRecord::Base
  include DateHelper
  resourcify

  # Use the format slug for urls. e.g. /events/myshow
  def to_param
    slug
  end

  # Scopes #

  # Usually order events with the earliest at the top.
  default_scope -> { order('start_date ASC') }

  scope :current, -> { where(['end_date >= ? AND is_public = ?', Date.current, true]) }
  scope :future, -> { where(['end_date >= ?', Date.current]) }

  def self.current_slideshow
    return unscoped.where(['end_date >= ? AND is_public = ?', Date.current, true]).order('end_date ASC')
  end

  # Relationships #

  has_many :team_members, class_name: '::TeamMember', as: :teamwork, dependent: :destroy
  has_many :users, through: :team_members
  has_many :pictures, as: :gallery, dependent: :destroy

  belongs_to :venue
  belongs_to :season

  accepts_nested_attributes_for :team_members, reject_if: :all_blank, allow_destroy: true
  accepts_nested_attributes_for :pictures, reject_if: :all_blank, allow_destroy: true

  # Validations #

  # Do not validate start_date, end_date or tag_line, as these will cause the proposal to show conversion to fail.
  validates :name, :description, presence: true
  validates :slug, presence: true, uniqueness: true

  # Paperclip #
  has_attached_file :image,
                    styles: { medium: '576x300#', thumb: '192x100#', slideshow: '960x500#' },
                    convert_options: { medium: '-strip', thumb: '-quality 75 -strip' },
                    default_url: :default_image

  validates_attachment :image, content_type: { content_type: ["image/jpg", "image/jpeg", "image/png", "image/gif"] }

  # Accessible Attributes #
  attr_accessible :description, :name, :slug, :tagline, :author, :venue, :venue_id, :season, :season_id, :xts_id, :is_public, :image, :start_date, :end_date, :team_members, :team_members_attributes, :pictures, :pictures_attributes, :price, :spark_seat_slug

  # Returns the last show to have finished.
  def self.last_show
    return where(['end_date < ? AND is_public = ?', Date.current, true]).last
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
    return date_range_string(start_date, end_date, include_year, format)
  end

  def as_json(options = {})
    defaults = {
      include: [
        :venue
      ]
    }

    options = options.merge(defaults) do |_key, oldval, newval|
      # http://stackoverflow.com/a/11171921
      (newval.is_a?(Array) ? (oldval + newval) : (oldval << newval)).uniq
    end

    super(options)
  end
end
