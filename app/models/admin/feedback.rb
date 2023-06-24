##
# Represents feedback for a Show.
#
# == Schema Information
#
# Table name: admin_feedbacks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *show_id*::    <tt>integer</tt>
# *body*::       <tt>text(65535)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Admin::Feedback < ApplicationRecord
  validates :show_id, :body, presence: true
  belongs_to :show, class_name: 'Show'

  def self.ransackable_attributes(auth_object = nil)
    %w[body show_id]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[show]
  end
end
