##
# Nothing really interesting about news. It's news.
#
# ==Paperclip
# Images are stored as:
# * medium (x300)
# * thumb  (150x100)
#
# == Schema Information
#
# Table name: news
#
#  id                 :integer          not null, primary key
#  title              :string(255)
#  body               :text
#  slug               :string(255)
#  publish_date       :datetime
#  show_public        :boolean
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  image_file_name    :string(255)
#  image_content_type :string(255)
#  image_file_size    :integer
#  image_updated_at   :datetime
##

class News < ActiveRecord::Base
  resourcify

  ##
  # Use the format id-slug for urls. e.g. /news/1-mynews
  ##
  def to_param
    "#{id}-#{slug}"
  end

  validates :title, :presence => true
  validates :publish_date, :presence => true
  validates :slug, :presence => true, :uniqueness => true

  scope :current, where(["publish_date <= ?", Date.current]).order("publish_date DESC")

  has_attached_file :image, :styles => { :medium => "x300>", :thumb => "192x100#" }
  attr_accessible :publish_date, :show_public, :slug, :title, :body, :image
end
