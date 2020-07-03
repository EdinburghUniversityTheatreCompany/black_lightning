# == Schema Information
#
# Table name: marketing_creatives_profiles
#
# *id*::         <tt>bigint, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *url*::        <tt>string(255)</tt>
# *about*::      <tt>text(65535)</tt>
# *approved*::   <tt>boolean</tt>
# *user_id*::    <tt>integer</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
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
