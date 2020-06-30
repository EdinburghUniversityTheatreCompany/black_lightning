class MarketingCreatives::Category < ApplicationRecord
  validates :name, :url, :name_on_profile, presence: true, uniqueness: { case_sensitive: true }

  acts_as_url :name

  has_many :category_infos, class_name: 'MarketingCreatives::CategoryInfo', dependent: :restrict_with_error
  has_many :profiles, through: :category_infos
  
  has_one_attached :image
  validates :image, content_type: %i[png jpg jpeg gif]

  def to_param
    url
  end

  ##
  # Display kittens if the image for whatever reason does not exist.
  ##
  def fetch_image
    image.attach(ApplicationController.helpers.default_image_blob('missing.png')) unless image.attached? 

    return image
  end
end
