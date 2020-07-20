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

  # Everyone can create and it should not be possible to delete complaints.
  DISABLED_PERMISSIONS = %w[create destroy].freeze

  def html_class
    return 'error' unless resolved
  end

  private

  def stop_destroy
    self.errors[:base] << 'Complaints cannot be deleted'
    throw :abort
  end
end
