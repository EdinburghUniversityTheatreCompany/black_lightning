# == Schema Information
#
# Table name: maintenance_sessions
# Database name: primary
#
#  id         :bigint           not null, primary key
#  date       :date
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class MaintenanceSession < ApplicationRecord
    validates :date, presence: true

    has_many :maintenance_attendances, dependent: :restrict_with_error
    has_many :users, through: :maintenance_attendances

    accepts_nested_attributes_for :maintenance_attendances, reject_if: :all_blank, allow_destroy: true

    def self.ransackable_attributes(auth_object = nil)
        %w[date]
    end

    def self.ransackable_associations(auth_object = nil)
        %w[maintenance_attendances users]
    end

    def to_label
        date
    end
end
