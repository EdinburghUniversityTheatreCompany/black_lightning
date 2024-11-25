# == Schema Information
#
# Table name: fault_reports
#
# *id*::             <tt>integer, not null, primary key</tt>
# *item*::           <tt>string(255)</tt>
# *description*::    <tt>text(65535)</tt>
# *severity*::       <tt>integer, default("annoying")</tt>
# *status*::         <tt>integer, default("reported")</tt>
# *reported_by_id*:: <tt>integer</tt>
# *fixed_by_id*::    <tt>integer</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class FaultReport < ApplicationRecord
  validates :item, :description, presence: true

  belongs_to :reported_by,  class_name: 'User'
  belongs_to :fixed_by,     class_name: 'User', optional: true

  normalizes :item, with: -> (item) { item&.strip }

  enum :severity, 
    annoying: 0,
    probably_worth_fixing: 1,
    show_impeding: 2,
    dangerous: 3,
    no_fault: 4

  enum :status, 
    reported: 0,
    in_progress: 1,
    cant_fix: 2,
    wont_fix: 3,
    on_hold: 4,
    completed: 5

  def self.ransackable_attributes(auth_object = nil)
    %w[description fixed_by_id item reported_by_id severity status created_at updated_at]
  end

  def reported_by_name
    return reported_by.try(:name) || 'Unknown'
  end

  def fixed_by_name
    return fixed_by.try(:name) || 'Unknown'
  end

  def css_class
    case status.to_sym
    when :in_progress, :on_hold
      return 'table-warning'
    when :cant_fix, :wont_fix
      return 'table-danger'
    when :completed
      return 'table-success'
    else
      return ''
    end
  end
end
