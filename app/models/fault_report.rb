class FaultReport < ApplicationRecord
  validates :item, :description, presence: true

  belongs_to :reported_by,  class_name: User
  belongs_to :fixed_by,     class_name: User

  enum severity: %I[annoying probably_worth_fixing show_impeding dangerous]
  enum status: %I[reported in_progress cant_fix wont_fix on_hold completed]

  def reported_by_name
    return reported_by.try(:name) || 'Unknown'
  end

  def fixed_by_name
    return reported_by.try(:name) || 'Unknown'
  end
end
