class Show < ActiveRecord::Base
  resourcify
  def to_param
    slug
  end

  scope :current, where(["end_date >= ? AND is_public = ?", Date.current, true]).order("start_date ASC")

  has_many :team_members, :class_name => "::TeamMember", :as => :teamwork
  has_many :users, :through => :team_members

  accepts_nested_attributes_for :team_members

  validates :name, :description, :presence => true
  validates :slug, :presence => true, :uniqueness => true

  has_attached_file :image, :styles => { :medium => "x300>", :thumb => "x100>", :slideshow => "960x500#" }
  attr_accessible :description, :name, :slug, :tagline, :xts_id, :is_public, :image, :start_date, :end_date, :team_members, :team_members_attributes

  def date_range
    date = I18n.l(self.start_date, :format => :short)

    if self.end_date then
        date << " - "
        date << I18n.l(self.end_date, :format => :short)
    end
  end
end
