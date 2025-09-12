# == Schema Information
#
# Table name: complaints
#
# *id*::          <tt>bigint, not null, primary key</tt>
# *subject*::     <tt>text(65535)</tt>
# *description*:: <tt>text(65535)</tt>
# *comments*::    <tt>text(65535)</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Complaint < ApplicationRecord
  has_paper_trail

  validates :subject, :description, presence: true

  before_destroy :stop_destroy

  normalizes :subject, with: ->(subject) { subject&.strip }

  # Everyone can create and it should not be possible to delete complaints.
  DISABLED_PERMISSIONS = %w[create destroy].freeze

  def html_class
    "error" unless resolved
  end

  def self.ransackable_attributes(auth_object = nil)
    # By default, there should be an accessible_by call on this, but just to be safe, I am also including it here.
    return unless auth_object.can?(:index, Complaint)

    %w[subject description comments]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "versions" ]
  end

  private

  def stop_destroy
    self.errors.add(:base, "Complaints cannot be deleted")
    throw :abort
  end
end
