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
  validates :name, length: { maximum: 255 }
    # Most credits one person can be granted in one session.
    MAX_CREDITS_PER_ATTENDEE = 200

    validates :date, presence: true

    has_many :maintenance_credits, dependent: :restrict_with_error
    has_many :users, through: :maintenance_credits

    # allow_destroy turns on autosave, which saves what #maintenance_credits_attributes= builds and
    # marks for destruction. That setter replaces Rails' own, so it skips blank rows, not reject_if.
    accepts_nested_attributes_for :maintenance_credits, allow_destroy: true

    # Each credit's save reallocates its user's debts; this does it once per user instead.
    around_save :reallocate_attendee_debts_once

    def self.ransackable_attributes(auth_object = nil)
        %w[date name]
    end

    def self.ransackable_associations(auth_object = nil)
        %w[maintenance_credits users]
    end

    def to_label
        name.presence || date
    end

    # One credit per user, carrying their count as +quantity+. Reads the loaded association, not a
    # query, so unsaved rows survive a failed save's re-render.
    def attendees_for_form
        maintenance_credits
            .reject(&:marked_for_destruction?)
            .group_by(&:user_id)
            .map { |_user_id, group| group.first.tap { |rep| rep.quantity = group.size } }
    end

    # Builds or destroys credits until each user has the submitted quantity. A removed row
    # (_destroy) or a zero removes all of them.
    def maintenance_credits_attributes=(attributes)
        rows = attributes.respond_to?(:values) ? attributes.values : attributes

        desired = Hash.new(0) # user_id => target credit count
        rows.each do |row|
            attrs = row.to_h.symbolize_keys
            user_id = attrs[:user_id].presence || attrs[:user].presence ||
                      maintenance_credits.detect { |att| att.id.to_s == attrs[:id].to_s }&.user_id
            next if user_id.blank?

            count = if ActiveModel::Type::Boolean.new.cast(attrs[:_destroy])
                0
            elsif attrs[:quantity].present?
                attrs[:quantity].to_i.clamp(0, MAX_CREDITS_PER_ATTENDEE)
            else
                1 # no quantity means one credit
            end
            desired[user_id.to_i] += count
        end

        existing_by_user = maintenance_credits.reject(&:marked_for_destruction?).group_by(&:user_id)

        # The form renders every attendee, so a user missing from the submission drops to zero.
        (desired.keys | existing_by_user.keys).each do |user_id|
            want = desired[user_id]
            have = existing_by_user[user_id] || []

            if want > have.size
                (want - have.size).times { maintenance_credits.build(user_id: user_id) }
                pending_reallocation_user_ids << user_id
            elsif want < have.size
                # Prefer credits not yet matched to a debt.
                have.sort_by { |att| att.maintenance_debt ? 1 : 0 }
                    .first(have.size - want)
                    .each(&:mark_for_destruction)
                pending_reallocation_user_ids << user_id
            end
        end
    end

    private

    # Users whose credit count changed, so their debts need rematching.
    def pending_reallocation_user_ids
        @pending_reallocation_user_ids ||= Set.new
    end

    # Reallocates only after a successful save, inside its transaction.
    def reallocate_attendee_debts_once
        previous = User.suppress_maintenance_reallocation
        User.suppress_maintenance_reallocation = true
        yield
        User.suppress_maintenance_reallocation = previous

        ids = pending_reallocation_user_ids
        User.where(id: ids).find_each(&:reallocate_maintenance_debts) if ids.any?
        @pending_reallocation_user_ids = Set.new
    ensure
        User.suppress_maintenance_reallocation = previous
    end
end
