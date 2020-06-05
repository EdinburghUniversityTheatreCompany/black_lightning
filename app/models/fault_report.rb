class FaultReport < ApplicationRecord
  validates :item, :description, presence: true

  belongs_to :reported_by,  class_name: 'User'
  belongs_to :fixed_by,     class_name: 'User'

  enum severity: %I[annoying probably_worth_fixing show_impeding dangerous]
  enum status: %I[reported in_progress cant_fix wont_fix on_hold completed]

  def reported_by_name
    return reported_by.try(:name) || 'Unknown'
  end

  def fixed_by_name
    return fixed_by.try(:name) || 'Unknown'
  end

  def css_class
    case status.to_sym
    when :in_progress, :on_hold
      return 'warning'
    when :cant_fix, :wont_fix
      return 'error'
    when :completed
      return 'success'
    else
      return ''
    end
  end
end