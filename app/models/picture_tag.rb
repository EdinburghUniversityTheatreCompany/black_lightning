# == Schema Information
#
# Table name: picture_tags
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class PictureTag < ApplicationRecord
  validates :name, :description, presence: true
  validates :name, uniqueness: { case_sensitive: false }

  has_and_belongs_to_many :pictures, optional: true

  normalizes :name, with: ->(name) { name&.strip }

  def self.ransackable_attributes(auth_object = nil)
    %w[description name id ordering]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[pictures]
  end
end
