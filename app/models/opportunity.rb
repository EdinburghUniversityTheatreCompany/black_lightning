# == Schema Information
#
# Table name: opportunities
#
# *id*::          <tt>integer, not null, primary key</tt>
# *title*::       <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *show_email*::  <tt>boolean</tt>
# *approved*::    <tt>boolean</tt>
# *creator_id*::  <tt>integer</tt>
# *approver_id*:: <tt>integer</tt>
# *expiry_date*:: <tt>date</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Opportunity < ApplicationRecord
  belongs_to :creator,  class_name: 'User'
  belongs_to :approver, class_name: 'User', optional: true

  validates :title, :expiry_date, :description, :creator_id, presence: true

  # If you update this, you must also update the active? method and the permission somewhere at the top of ability.rb.
  # You might also have to update the opportunities helper.
  scope :active, -> { where('approved = true AND expiry_date > ?', Time.now).order('expiry_date ASC') }

  def active?
    return approved && expiry_date > Time.now
  end

  def css_class
    return '' unless expiry_date > Time.now

    if active?
      return 'table-success'.html_safe
    else
      return 'table-danger'.html_safe
    end
  end
end
