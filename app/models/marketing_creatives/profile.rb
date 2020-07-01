class MarketingCreatives::Profile < ApplicationRecord
  validates :name, :about, :url, presence: true
  validates :user, :name, :url, uniqueness: { case_sensitive: true }, allow_nil: true

  acts_as_url :name

  has_many :category_infos, class_name: 'MarketingCreatives::CategoryInfo', dependent: :restrict_with_error
  has_many :categories, through: :category_infos
  accepts_nested_attributes_for :category_infos, reject_if: :all_blank, allow_destroy: true

  belongs_to :user, optional: true

  def to_param
    url
  end
end
