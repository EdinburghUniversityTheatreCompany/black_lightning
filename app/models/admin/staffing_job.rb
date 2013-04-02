##
# Represents a job/position that may need to be staffed.
#
# == Schema Information
#
# Table name: admin_staffing_jobs
#
# *id*::             <tt>integer, not null, primary key</tt>
# *name*::           <tt>string(255)</tt>
# *staffable_id*::   <tt>integer</tt>
# *user_id*::        <tt>integer</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
# *staffable_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
##
class Admin::StaffingJob < ActiveRecord::Base
  belongs_to :staffable, :polymorphic => true
  belongs_to :user

  validates :name, :presence => true

  attr_accessible :name, :user, :user_id

  ##
  # Get the start time in a js friendly fashion
  ##
  def js_start_time
    return staffable.start_time.utc.to_i
  end

  ##
  # Get the end time in a js friendly fashion
  ##
  def js_end_time
    return staffable.end_time.utc.to_i
  end
end
