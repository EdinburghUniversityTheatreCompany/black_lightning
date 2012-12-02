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
#

class Show < ActiveRecord::Base
  resourcify
  def to_param
    slug
  end

  default_scope order("start_date ASC")

  scope :current, where(["end_date >= ? AND is_public = ?", Date.current, true])
  scope :future, where(["end_date >= ?", Date.current])
  def self.last_show
    return self.where(["end_date <= ? AND is_public = ?", Date.current, true]).first
  end

  has_many :team_members, :class_name => "::TeamMember", :as => :teamwork
  has_many :users, :through => :team_members
  has_many :pictures, :as => :gallery

  belongs_to :venue

  accepts_nested_attributes_for :team_members
  accepts_nested_attributes_for :pictures, :reject_if => :all_blank, :allow_destroy => true

  #Do not validate start_date, end_date or tag_line, as these will cause the proposal to show conversion to fail.
  validates :name, :description, :presence => true
  validates :slug, :presence => true, :uniqueness => true

  has_attached_file :image, :styles => { :medium => "x300>", :thumb => "150x100", :slideshow => "960x500#" }, :default_url => :default_image
  attr_accessible :description, :name, :slug, :tagline, :venue, :venue_id, :xts_id, :is_public, :image, :start_date, :end_date, :team_members, :team_members_attributes, :pictures, :pictures_attributes

  def default_image
    number = self.id.modulo(4)
    return "/images/generic_shows/:style/#{number}.png"
  end

  def date_range
    if not self.start_date.presence then
      return
    end

    date = I18n.l(self.start_date, :format => :short)

    if self.end_date then
        date << " - "
        date << I18n.l(self.end_date, :format => :short)
    end
  end

  def create_questionnaire
    questionnaire = Admin::Questionnaires::Questionnaire.new
    questionnaire.show = self
    questionnaire.save
  end
  handle_asynchronously :create_questionnaire
end
