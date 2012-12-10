##
# Represents a job/position that may need to be staffed.
#
# == Schema Information
#
# Table name: admin_staffing_jobs
#
# *id*::          <tt>integer, not null, primary key</tt>
# *name*::        <tt>string(255)</tt>
# *staffing_id*:: <tt>integer</tt>
# *user_id*::     <tt>integer</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
##
class Admin::StaffingJob < ActiveRecord::Base
  belongs_to :staffing, :class_name => "Admin::Staffing"
  belongs_to :user

  validates :name, :presence => true

  attr_accessible :name, :user, :user_id
end
