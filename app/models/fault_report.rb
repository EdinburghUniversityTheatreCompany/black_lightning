# == Schema Information
#
# Table name: fault_reports
# Database name: primary
#
#  id             :integer          not null, primary key
#  description    :text(16777215)
#  item           :string(255)
#  severity       :integer          default("annoying")
#  status         :integer          default("reported")
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  fixed_by_id    :integer
#  reported_by_id :integer
#
# Indexes
#
#  index_fault_reports_on_fixed_by_id     (fixed_by_id)
#  index_fault_reports_on_reported_by_id  (reported_by_id)
#  index_fault_reports_on_severity        (severity)
#  index_fault_reports_on_status          (status)
#
class FaultReport < ApplicationRecord
  # Length validations enforcing database column limits
  validates :item, length: { maximum: 255 }
  validates :description, length: { maximum: 16777215 }
  validates :item, :description, presence: true

  belongs_to :reported_by,  class_name: "User"
  belongs_to :fixed_by,     class_name: "User", optional: true

  normalizes :item, with: ->(item) { item&.strip }

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
    reported_by.try(:name) || "Unknown"
  end

  def fixed_by_name
    fixed_by.try(:name) || "Unknown"
  end

  def css_class
    case status.to_sym
    when :in_progress, :on_hold
      "table-warning"
    when :cant_fix, :wont_fix
      "table-danger"
    when :completed
      "table-success"
    else
      ""
    end
  end
end
