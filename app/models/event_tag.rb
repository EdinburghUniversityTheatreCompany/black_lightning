# == Schema Information
#
# Table name: event_tags
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class EventTag < ApplicationRecord
  validates :name, :description, presence: true
  validates :name, uniqueness: { case_sensitive: false }

  has_and_belongs_to_many :events, optional: true

  default_scope { order(:ordering) }

  def self.ransackable_attributes(auth_object = nil)
    %w[description id name ordering]
  end
end
