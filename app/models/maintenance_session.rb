# == Schema Information
#
# Table name: maintenance_sessions
# Database name: primary
#
#  id         :bigint           not null, primary key
#  date       :date
#  name       :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class MaintenanceSession < ApplicationRecord
    # Upper bound on how many credits (attendances) a single person can be granted in one session.
    MAX_CREDITS_PER_ATTENDEE = 20

    validates :date, presence: true

    has_many :maintenance_attendances, dependent: :restrict_with_error
    has_many :users, through: :maintenance_attendances

    # allow_destroy gives the association autosave, so attendances built/marked for destruction in
    # #maintenance_attendances_attributes= are persisted/deleted when the session is saved.
    accepts_nested_attributes_for :maintenance_attendances, reject_if: :all_blank, allow_destroy: true

    def self.ransackable_attributes(auth_object = nil)
        %w[date name]
    end

    def self.ransackable_associations(auth_object = nil)
        %w[maintenance_attendances users]
    end

    def to_label
        name.presence || date
    end

    # One representative attendance per user, carrying the user's credit count as +quantity+, so the
    # form can show a single row per person instead of one row per credit.
    def attendees_for_form
        maintenance_attendances.includes(:user)
            .reject(&:marked_for_destruction?)
            .group_by(&:user_id)
            .map { |_user_id, group| group.first.tap { |rep| rep.quantity = group.size } }
    end

    # Reconciles the per-user credit quantities submitted by the form against the existing
    # attendances: builds new ones when a count goes up, destroys surplus ones when it goes down, and
    # destroys all of a user's attendances when their row is removed (_destroy) or set to zero.
    def maintenance_attendances_attributes=(attributes)
        rows = attributes.respond_to?(:values) ? attributes.values : attributes

        desired = Hash.new(0) # user_id => target credit count
        rows.each do |row|
            attrs = row.to_h.symbolize_keys
            user_id = attrs[:user_id].presence || attrs[:user].presence ||
                      maintenance_attendances.detect { |att| att.id.to_s == attrs[:id].to_s }&.user_id
            next if user_id.blank?

            count = if ActiveModel::Type::Boolean.new.cast(attrs[:_destroy])
                0
            elsif attrs[:quantity].present?
                attrs[:quantity].to_i.clamp(0, MAX_CREDITS_PER_ATTENDEE)
            else
                1 # a listed user with no explicit quantity counts as one credit
            end
            desired[user_id.to_i] += count
        end

        existing_by_user = maintenance_attendances.reject(&:marked_for_destruction?).group_by(&:user_id)

        # The form renders every current attendee, so the submitted rows are the complete desired
        # set: any existing user no longer present (row removed, or its user reassigned) drops to 0.
        (desired.keys | existing_by_user.keys).each do |user_id|
            want = desired[user_id]
            have = existing_by_user[user_id] || []

            if want > have.size
                (want - have.size).times { maintenance_attendances.build(user_id: user_id) }
            elsif want < have.size
                # Destroy surplus, preferring attendances not yet matched to a debt.
                have.sort_by { |att| att.maintenance_debt ? 1 : 0 }
                    .first(have.size - want)
                    .each(&:mark_for_destruction)
            end
        end
    end
end
