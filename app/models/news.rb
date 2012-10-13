class News < ActiveRecord::Base
  resourcify
  def to_param
    "#{id}-#{slug}"
  end
  
  validates :title, :presence => true
  validates :publish_date, :presence => true
  validates :slug, :presence => true, :uniqueness => true

  attr_accessible :publish_date, :show_public, :slug, :title, :body
end
