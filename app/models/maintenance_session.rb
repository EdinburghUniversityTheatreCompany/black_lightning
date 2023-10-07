# == Schema Information
#
# Table name: maintenance_sessions
#
# *id*::         <tt>bigint, not null, primary key</tt>
# *date*::       <tt>date</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class MaintenanceSession < ApplicationRecord
    validates :date, presence: true

    has_many :maintenance_attendances
    has_many :users, through: :maintenance_attendances

    accepts_nested_attributes_for :maintenance_attendances, reject_if: :all_blank, allow_destroy: true

    def self.ransackable_attributes(auth_object = nil)
        %w[date]
    end

    def self.ransackable_associations(auth_object = nil)
        %w[maintenance_attendances]
    end

    def to_label
        date
    end
end
