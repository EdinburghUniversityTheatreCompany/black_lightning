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
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
    # Upper bound on how many credits (attendances) a single person can be granted in one session.
    MAX_CREDITS_PER_ATTENDEE = 200

    validates :date, presence: true

    has_many :maintenance_credits, dependent: :restrict_with_error
    has_many :users, through: :maintenance_credits

    # allow_destroy gives the association autosave, so attendances built/marked for destruction in
    # #maintenance_credits_attributes= are persisted/deleted when the session is saved. (That
    # custom setter fully replaces Rails' generated one, so reject_if would never run — blank rows
    # are skipped there instead.)
    accepts_nested_attributes_for :maintenance_credits, allow_destroy: true

    # Building/destroying N attendances for one user would otherwise fire that user's debt
    # reallocation N times (each attendance's after_save/after_destroy). Suppress the per-attendance
    # reallocation during the save and run it once per affected user afterwards instead.
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

    # One representative attendance per user, carrying the user's credit count as +quantity+, so the
    # form can show a single row per person instead of one row per credit. Iterates the in-memory
    # association (not a fresh query) so unsaved built rows survive a failed-save form re-render.
    def attendees_for_form
        maintenance_credits
            .reject(&:marked_for_destruction?)
            .group_by(&:user_id)
            .map { |_user_id, group| group.first.tap { |rep| rep.quantity = group.size } }
    end

    # Reconciles the per-user credit quantities submitted by the form against the existing
    # attendances: builds new ones when a count goes up, destroys surplus ones when it goes down, and
    # destroys all of a user's attendances when their row is removed (_destroy) or set to zero.
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
                1 # a listed user with no explicit quantity counts as one credit
            end
            desired[user_id.to_i] += count
        end

        existing_by_user = maintenance_credits.reject(&:marked_for_destruction?).group_by(&:user_id)

        # The form renders every current attendee, so the submitted rows are the complete desired
        # set: any existing user no longer present (row removed, or its user reassigned) drops to 0.
        (desired.keys | existing_by_user.keys).each do |user_id|
            want = desired[user_id]
            have = existing_by_user[user_id] || []

            if want > have.size
                (want - have.size).times { maintenance_credits.build(user_id: user_id) }
                pending_reallocation_user_ids << user_id
            elsif want < have.size
                # Destroy surplus, preferring attendances not yet matched to a debt.
                have.sort_by { |att| att.maintenance_debt ? 1 : 0 }
                    .first(have.size - want)
                    .each(&:mark_for_destruction)
                pending_reallocation_user_ids << user_id
            end
        end
    end

    private

    # Users whose credit count changed in this save and so need their debts rematched once.
    def pending_reallocation_user_ids
        @pending_reallocation_user_ids ||= Set.new
    end

    # Suppresses each attendance's inline reallocation while the batch of built/destroyed
    # attendances is persisted, then reallocates every affected user exactly once. The flush runs
    # only on a successful save and stays inside the save transaction (matching the old behaviour).
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
