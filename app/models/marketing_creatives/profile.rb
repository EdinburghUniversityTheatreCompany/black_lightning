# == Schema Information
#
# Table name: marketing_creatives_profiles
# Database name: primary
#
#  id         :bigint           not null, primary key
#  about      :text(16777215)
#  approved   :boolean
#  contact    :text(16777215)
#  name       :string(255)
#  url        :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer
#
# Indexes
#
#  index_marketing_creatives_profiles_on_url      (url)
#  index_marketing_creatives_profiles_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class MarketingCreatives::Profile < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :url, length: { maximum: 255 }
  validates :about, length: { maximum: 16777215 }
  validates :contact, length: { maximum: 16777215 }
  validates :name, :about, :contact, :url, presence: true
  validates :user, :name, :url, uniqueness: { case_sensitive: true }, allow_nil: true

  acts_as_url :name

  has_many :category_infos, class_name: "MarketingCreatives::CategoryInfo", dependent: :restrict_with_error
  has_many :categories, through: :category_infos
  accepts_nested_attributes_for :category_infos, reject_if: :all_blank, allow_destroy: true

  belongs_to :user, optional: true

  normalizes :name, :url, with: ->(value) { value&.strip }

  def to_param
    url
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "about", "approved", "contact", "name", "url", "user_id" ]
  end
end
