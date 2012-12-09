##
# Probably the most important model in the app.
#
# Note that urls are generated to include the slug rather than the id of a show.
# Therefore, all lookups must be done as follows:
#  @show = Show.find_by_slug(params[:id])
#
# == Schema Information
#
# Table name: shows
#
#  id                 :integer          not null, primary key
#  name               :string(255)
#  tagline            :string(255)
#  slug               :string(255)
#  description        :text
#  xts_id             :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  is_public          :boolean
#  image_file_name    :string(255)
#  image_content_type :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
#  start_date         :date
#  end_date           :date
#  venue_id           :integer
##

class Show < ActiveRecord::Base
  resourcify

  # Use the format slug for urls. e.g. /shows/myshow
  def to_param
    slug
  end

  # Scopes #

  # Usually order shows with the earliest at the top.
  default_scope order("start_date ASC")

  scope :current, where(["end_date >= ? AND is_public = ?", Date.current, true])
  scope :future, where(["end_date >= ?", Date.current])

  # Relationships #

  has_many :team_members, :class_name => "::TeamMember", :as => :teamwork
  has_many :users, :through => :team_members
  has_many :pictures, :as => :gallery
  has_many :reviews

  has_many :feedbacks, :class_name => "Admin::Feedback"
  has_many :questionnaires, :class_name => "Admin::Questionnaires::Questionnaire"

  belongs_to :venue

  accepts_nested_attributes_for :team_members
  accepts_nested_attributes_for :pictures, :reject_if => :all_blank, :allow_destroy => true
  accepts_nested_attributes_for :reviews, :reject_if => :all_blank, :allow_destroy => true

  # Validations #

  #Do not validate start_date, end_date or tag_line, as these will cause the proposal to show conversion to fail.
  validates :name, :description, :presence => true
  validates :slug, :presence => true, :uniqueness => true

  # Paperclip #
  has_attached_file :image, :styles => { :medium => "576x300#", :thumb => "192x100#", :slideshow => "960x500#" }, :default_url => :default_image

  # Accessible Attributes #
  attr_accessible :description, :name, :slug, :tagline, :venue, :venue_id, :xts_id, :is_public, :image, :start_date, :end_date, :team_members, :team_members_attributes, :pictures, :pictures_attributes, :reviews, :reviews_attributes

  # Returns the last show to have finished.
  def self.last_show
    return self.where(["end_date <= ? AND is_public = ?", Date.current, true]).first
  end

  ##
  # Generates a default image for the show. If extra artwork is added, increase the base of the modulo call.
  #
  # NOTE: The first image must have filename 0.png - remember that in modulo 4 (for example), valid numbers are 0,1,2,3 (not 4)!
  ##
  def default_image
    number = self.id.modulo(4)
    return "/images/generic_shows/:style/#{number}.png"
  end

  ##
  # Generates the frequently used "startdate - enddate" string.
  #
  # The date format used is the :long format, defined in /config/locales/en.yml
  ##
  def date_range
    if not self.start_date.presence then
      return
    end

    date = I18n.l(self.start_date, :format => :long)

    if self.end_date and not self.start_date == self.end_date then
        date << " - "
        date << I18n.l(self.end_date, :format => :long)
    end

    return date
  end

  ##
  # Task to create a questionnaire for the show.
  ##
  def create_questionnaire(name)
    questionnaire = Admin::Questionnaires::Questionnaire.new
    questionnaire.show = self
    questionnaire.name = name
    questionnaire.save
  end
end
