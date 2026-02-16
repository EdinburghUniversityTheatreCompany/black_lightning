##
# Model used by Devise for users.
#
# == Schema Information
#
# Table name: users
#
# *id*::                     <tt>integer, not null, primary key</tt>
# *email*::                  <tt>string(255), default(""), not null</tt>
# *encrypted_password*::     <tt>string(255), default(""), not null</tt>
# *reset_password_token*::   <tt>string(255)</tt>
# *reset_password_sent_at*:: <tt>datetime</tt>
# *remember_created_at*::    <tt>datetime</tt>
# *sign_in_count*::          <tt>integer, default(0)</tt>
# *current_sign_in_at*::     <tt>datetime</tt>
# *last_sign_in_at*::        <tt>datetime</tt>
# *current_sign_in_ip*::     <tt>string(255)</tt>
# *last_sign_in_ip*::        <tt>string(255)</tt>
# *first_name*::             <tt>string(255)</tt>
# *last_name*::              <tt>string(255)</tt>
# *created_at*::             <tt>datetime, not null</tt>
# *updated_at*::             <tt>datetime, not null</tt>
# *phone_number*::           <tt>string(255)</tt>
# *public_profile*::         <tt>boolean, default(TRUE)</tt>
# *bio*::                    <tt>text(65535)</tt>
# *avatar_file_name*::       <tt>string(255)</tt>
# *avatar_content_type*::    <tt>string(255)</tt>
# *avatar_file_size*::       <tt>integer</tt>
# *avatar_updated_at*::      <tt>datetime</tt>
# *username*::               <tt>string(255)</tt>
# *remember_token*::         <tt>string(255)</tt>
# *consented*::              <tt>date</tt>
#--
# == Schema Information End
#++
class User < ApplicationRecord
  before_save :unify_numbers
  before_validation :extract_student_id_from_email, if: :email_changed?

  rolify
  has_paper_trail limit: 6

  ###############
  # Permissions
  ###############
  # Users have an additional permission called view_shows_and_bio.
  # If an user has this permission, they can see the bio, avatar, and shows of the user they have the permission for.
  # It allows you to keep read for people who can see ALL info, including email and phone number.
  # Guests have :view_shows_and_bio for all users who have set public_profile to true
  ##############

  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  # devise :ldap_authenticatable, :recoverable, :rememberable, :trackable, :registerable

  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  # set our own validations
  validates :phone_number, allow_blank: true, format: { with: /\A(\(?\+?[0-9]*\)?)?[0-9_\- \(\)]*\z/, message: "Please enter a valid mobile number" }
  validates :email, presence: true

  validates :avatar, content_type: %i[png jpg jpeg gif]
  validates :student_id,
    format: {
      with: /\As\d{7}\z/,
      message: "must be in format s1234567 (s followed by 7 digits)",
      allow_blank: true
    }
  validates :associate_id,
    format: {
      with: /\AASSOC\d+\z/i,
      message: "must be in format ASSOC123456 (ASSOC followed by digits)",
      allow_blank: true
    }

  has_one :marketing_creatives_profile, class_name: "MarketingCreatives::Profile", dependent: :restrict_with_error

  has_one  :membership_card, dependent: :destroy
  delegate :card_number, to: :membership_card, allow_nil: true
  accepts_nested_attributes_for :membership_card, reject_if: :all_blank, allow_destroy: true

  has_many :team_membership, class_name: "TeamMember", dependent: :restrict_with_error
  has_many :shows, through: :team_membership, source: :teamwork, source_type: "Show"
  has_many :staffing_jobs, class_name: "Admin::StaffingJob", dependent: :restrict_with_error
  has_many :staffings, through: :staffing_jobs, source: :staffable, source_type: "Admin::Staffing"
  has_many :admin_maintenance_debts, class_name: "Admin::MaintenanceDebt", dependent: :restrict_with_error
  has_many :admin_staffing_debts, class_name: "Admin::StaffingDebt", dependent: :restrict_with_error
  has_many :admin_debt_notifications, class_name: "Admin::DebtNotification", dependent: :destroy
  has_many :maintenance_attendances, class_name: "MaintenanceAttendance", dependent: :restrict_with_error

  has_one_attached :avatar

  normalizes :email, with: lambda { |email|
    return nil if email.nil?

    normalized = email.strip.downcase
    if normalized.match?(/^s\d{7}@sms\.ed\.ac\.uk$/)
      normalized.sub("@sms.ed.ac.uk", "@ed.ac.uk")
    else
      normalized
    end
  }
  normalizes :first_name, :last_name, :username, with: ->(name) { name&.strip }
  normalizes :associate_id, with: ->(id) { id&.strip&.upcase }

  default_scope -> { order("last_name ASC") }

  scope :profile_incomplete, -> { where(profile_completed_at: nil) }
  scope :profile_complete, -> { where.not(profile_completed_at: nil) }

  # Also change the method 'consented'
  def self.not_consented
    where(consented: Date.current.advance(years: -100)..Date.current.advance(years: -1))
  end

  def self.by_first_name
    reorder("first_name ASC")
  end

  def self.find_by_profile_completion_token(token)
    find_signed(token, purpose: :profile_completion)
  end

  def self.ransackable_attributes(auth_object = nil)
    attributes = %w[first_name last_name full_name]
    attributes += %w[bio email public_profile] if auth_object.can?(:read, User)
    attributes += %w[activation_state consented email ever_activated phone_number username sign_in_count student_id associate_id member_id] if auth_object.can?(:manage, User)

    attributes
  end

  def self.ransackable_associations(auth_object = nil)
    [ "admin_debt_notifications", "admin_maintenance_debts", "admin_staffing_debts", "marketing_creatives_profile", "roles", "shows", "staffing_jobs", "staffings", "versions" ]
  end

  def ability
    @ability ||= Ability.new(self)
  end

  delegate :can?, :cannot?, to: :ability

  # Returns the name if present, and the email if the user has the permission.
  # Can also be the current_ability instead of the current_user.
  # Should be your primary option of displaying a name
  def name(current_user = nil)
    if current_user.present? && current_user.can?(:show, self)
      name_or_email
    else
      name_or_default
    end
  end

  # Returns true if the users first_name and last_name are set.
  def name?
    first_name.present? && last_name.present?
  end

  # A quick way of getting the user's full name.
  def name_or_default
    return full_name unless full_name.blank?

    "No Name Set"
  end

  def full_name
    "#{first_name} #{last_name}".strip
  end

  # A quick way to get the user's full name, if they have a name, or their email.
  # Does not check for permissions.
  def name_or_email
    return name_or_default if name?

    email
  end

  # Ensures that all phone numbers begin with +44 and don't have any spaces in.
  def unify_numbers
    return unless phone_number

    self.phone_number = phone_number.gsub(/\s/, "")

    if phone_number[0] == "0"
      phone_number[0] = "+44"
    end
  end

  ransacker :full_name, formatter: proc { |v| v.downcase } do |parent|
    # Alternative
    # Arel.sql("CONCAT_WS(' ', users.first_name, users.last_name)")
    Arel::Nodes::NamedFunction.new("LOWER",
      [ Arel::Nodes::NamedFunction.new("concat_ws",
        [ Arel::Nodes::SqlLiteral.new("' '"), parent.table[:first_name], parent.table[:last_name] ]) ])
  end

  # Combined ransacker for searching both student_id and associate_id
  ransacker :member_id, formatter: proc { |v| v.to_s.upcase } do |parent|
    Arel::Nodes::NamedFunction.new("UPPER",
      [ Arel::Nodes::NamedFunction.new("COALESCE",
        [ Arel::Nodes::NamedFunction.new("concat_ws",
          [ Arel::Nodes::SqlLiteral.new("' '"), parent.table[:student_id], parent.table[:associate_id] ]),
          Arel::Nodes::SqlLiteral.new("''") ]) ])
  end

  ##
  # Creates a new user using the given params (e.g):
  #   User.new_user(params[:user])
  #
  # Generates a random password for the user if none is given.
  #
  # Will not save the new user.
  ##
  def self.new_user(params)
    user = User.new(params)

    unless user.password
      password_length = 6
      password = Devise.friendly_token.first(password_length)

      user.password = password
    end

    user
  end

  ##
  # Debt
  ##

  # The current and upcoming function share code, so please check them both if you change things.
  # Optimized to use single database queries instead of chaining where().unfulfilled
  def debt_causing_maintenance_debts(on_date = Date.current)
    admin_maintenance_debts.unfulfilled_before_date(on_date)
  end

  def upcoming_maintenance_debts(from_date = Date.current)
    admin_maintenance_debts.unfulfilled_after_date(from_date)
  end

  def debt_causing_staffing_debts(on_date = Date.current)
    admin_staffing_debts.unfulfilled_before_date(on_date)
  end

  def upcoming_staffing_debts(from_date = Date.current)
    admin_staffing_debts.unfulfilled_after_date(from_date)
  end

  def debt_message_suffix(on_date = Date.current)
    in_maintenance_debt = debt_causing_maintenance_debts(on_date).any?
    in_staffing_debt = debt_causing_staffing_debts(on_date).any?

    if in_maintenance_debt && in_staffing_debt
      "in staffing and maintenance Debt"
    elsif in_maintenance_debt
      "in maintenance Debt"
    elsif in_staffing_debt
      "in staffing Debt"
    else
      "not in Debt"
    end
  end

  # Returns true if the user is in debt
  # Rename to in debt?
  def in_debt(on_date = Date.current)
    debt_causing_maintenance_debts(on_date).any? || debt_causing_staffing_debts(on_date).any?
  end

  def self.in_debt(on_date = Date.current)
    # Use database-level query instead of loading all users into memory
    # A user is in debt if they have either:
    # 1. Maintenance debts that are unfulfilled and past due, OR
    # 2. Staffing debts that are unfulfilled and past due

    maintenance_debt_subquery = Admin::MaintenanceDebt
      .where(state: :normal)
      .where.missing(:maintenance_attendance)
      .where("due_by < ?", on_date)
      .select(:user_id)

    staffing_debt_subquery = Admin::StaffingDebt
      .where(admin_staffing_job: nil, state: :normal)
      .where("due_by < ?", on_date)
      .select(:user_id)

    where(
      id: maintenance_debt_subquery
    ).or(
      where(id: staffing_debt_subquery)
    ).distinct
  end

  # returns users who have been sent a notification since the given date
  def self.notified_since(date)
    includes(:admin_debt_notifications).where("admin_debt_notifications.sent_on > ?", date).references(:admin_debt_notifications).distinct
  end

  # Note: This function does not have any regard for permissions.
  def team_memberships(public_only)
    query = team_membership.where(teamwork_type: "Event")
                          .preload(teamwork: [ :venue, :season, { image_attachment: :blob } ])

    results = query.to_a

    if public_only
      results = results.select { |tm| tm.teamwork&.is_public }
    end

    results.sort_by { |tm| tm.teamwork&.start_date || Date.current }
  end

  # This method looks for all debts in the future and their attendances, all unallocated attendances, and all past debts without attendances.
  # It then matches all the soonest debt with attendances.
  def reallocate_maintenance_debts
    # Remove unnecessary reload calls and optimize query
    # Preload maintenance_attendance to prevent N+1 queries
    debts = admin_maintenance_debts
      .includes(:maintenance_attendance)
      .where("due_by >= ? ", Date.current)
      .or(admin_maintenance_debts.includes(:maintenance_attendance).where(maintenance_attendance: nil))
      .where(state: :normal)
      .order(due_by: :asc)
      .to_a

    attendances = maintenance_attendances
      .includes(:maintenance_debt)
      .where(admin_maintenance_debts: { id: [ nil ] + debts.map(&:id) })
      .to_a

    amount_of_pairs = [ debts.size, attendances.size ].min

    # Use transaction for bulk operations
    ActiveRecord::Base.transaction do
      # Prepare bulk updates
      updates_to_link = []
      updates_to_unlink = []

      # Link them as far as there are pairs
      (0...amount_of_pairs).each do |i|
        if debts[i].maintenance_attendance != attendances[i]
          updates_to_link << { id: debts[i].id, maintenance_attendance_id: attendances[i].id }
        end
      end

      # Unlink the rest
      (amount_of_pairs...debts.size).each do |i|
        if debts[i].maintenance_attendance.present?
          updates_to_unlink << { id: debts[i].id, maintenance_attendance_id: nil }
        end
      end

      # Perform bulk updates using update_all (more appropriate since we're only updating existing records)
      if updates_to_link.any?
        updates_to_link.each do |update|
          Admin::MaintenanceDebt.where(id: update[:id]).update_all(maintenance_attendance_id: update[:maintenance_attendance_id])
        end
      end

      if updates_to_unlink.any?
        debt_ids = updates_to_unlink.map { |u| u[:id] }
        Admin::MaintenanceDebt.where(id: debt_ids).update_all(maintenance_attendance_id: nil)
      end
    end
  end

  # This method looks for all debts in the future and their staffing jobs, all unallocated staffing jobs, and all past debts without jobs.
  # It then matches all the soonest debt with staffing jobs.
  def reallocate_staffing_debts
    # Remove unnecessary reload calls and optimize query
    # Preload admin_staffing_job to prevent N+1 queries
    debts = admin_staffing_debts
      .includes(:admin_staffing_job)
      .where("due_by >= ? ", Date.current)
      .or(admin_staffing_debts.includes(:admin_staffing_job).where(admin_staffing_job: nil))
      .where(state: :normal)
      .order(due_by: :asc)
      .to_a

    # Find all jobs for this user that are currently not associated or associated with a debt (belonging to this user) already.
    jobs = staffing_jobs
      .includes(:staffing_debt)
      .where(admin_staffing_debts: { id: [ nil ] + debts.map(&:id) })
      .to_a

    # Filter out jobs that do not count towards debt
    # Note: Cannot eager load polymorphic :staffable association, so this may cause N+1
    # but it's acceptable given the complexity of the alternative
    valid_jobs = jobs.select(&:counts_towards_debt?)

    # The amount of pairs is how many combinations of debt and staffing job there are.
    amount_of_pairs = [ debts.size, valid_jobs.size ].min

    # Use transaction for bulk operations
    ActiveRecord::Base.transaction do
      # Prepare bulk updates
      updates_to_link = []
      updates_to_unlink = []

      # Link them as far as there are pairs
      (0...amount_of_pairs).each do |i|
        if debts[i].admin_staffing_job != valid_jobs[i]
          updates_to_link << { id: debts[i].id, admin_staffing_job_id: valid_jobs[i].id }
        end
      end

      # Unlink the rest
      (amount_of_pairs...debts.size).each do |i|
        if debts[i].admin_staffing_job.present?
          updates_to_unlink << { id: debts[i].id, admin_staffing_job_id: nil }
        end
      end

      # Perform bulk updates using update_all (more appropriate since we're only updating existing records)
      if updates_to_link.any?
        updates_to_link.each do |update|
          Admin::StaffingDebt.where(id: update[:id]).update_all(admin_staffing_job_id: update[:admin_staffing_job_id])
        end
      end

      if updates_to_unlink.any?
        debt_ids = updates_to_unlink.map { |u| u[:id] }
        Admin::StaffingDebt.where(id: debt_ids).update_all(admin_staffing_job_id: nil)
      end
    end
  end

  ##
  # Merging Users
  ##

  # Returns count of staffing jobs not linked to any debt
  def staffing_jobs_unlinked_count
    staffing_jobs.left_joins(:staffing_debt).where(admin_staffing_debts: { id: nil }).count
  end

  # Returns count of staffing debts not linked to any job
  def staffing_debts_unlinked_count
    admin_staffing_debts.where(admin_staffing_job_id: nil, state: :normal).count
  end

  # Returns count of maintenance debts not linked to any attendance
  def maintenance_debts_unlinked_count
    admin_maintenance_debts.where(maintenance_attendance_id: nil, state: :normal).count
  end

  # Returns count of maintenance attendances not linked to any debt
  def maintenance_attendances_unlinked_count
    maintenance_attendances.left_joins(:maintenance_debt).where(admin_maintenance_debts: { id: nil }).count
  end

  # Returns count of team memberships that overlap with another user (same show/event)
  def overlapping_team_memberships_with(other_user)
    team_membership.where(
      teamwork_type: other_user.team_membership.select(:teamwork_type),
      teamwork_id: other_user.team_membership.select(:teamwork_id)
    ).count
  end

  # Returns merge statistics for preview modal
  def merge_stats_as_source(target_user)
    overlaps = target_user.overlapping_team_memberships_with(self)

    {
      team_memberships: {
        total: team_membership.count,
        overlapping: overlaps
      },
      staffing_jobs: {
        total: staffing_jobs.count,
        unlinked: staffing_jobs_unlinked_count
      },
      staffing_debts: {
        total: admin_staffing_debts.count,
        unlinked: staffing_debts_unlinked_count
      },
      maintenance_debts: {
        total: admin_maintenance_debts.count,
        unlinked: maintenance_debts_unlinked_count
      },
      maintenance_attendances: {
        total: maintenance_attendances.count,
        unlinked: maintenance_attendances_unlinked_count
      },
      roles: roles.pluck(:name)
    }
  end

  # Merges another user into this user, transferring all their associations.
  # The source_user will be destroyed after a successful merge.
  # keep_from_source: array of field names to copy from source user (e.g., ['name', 'email', 'student_id'])
  # Returns a hash with { success: boolean, errors: [], transferred: {} }
  def absorb(source_user, keep_from_source: [])
    return { success: false, errors: [ "Cannot merge user into itself" ] } if source_user&.id == id
    return { success: false, errors: [ "Source user not found" ] } if source_user.nil?

    transferred = {
      team_members: 0,
      staffing_jobs: 0,
      maintenance_debts: 0,
      staffing_debts: 0,
      debt_notifications: 0,
      maintenance_attendances: 0,
      roles: []
    }

    ActiveRecord::Base.transaction do
      # Apply field preferences from source user
      keep_from_source.each do |field|
        case field.to_s
        when "name"
          self.first_name = source_user.first_name
          self.last_name = source_user.last_name
        when "email"
          # Handle email swap to avoid uniqueness constraint
          if source_user.email != email
            source_email = source_user.email
            source_user.update_column(:email, "temp_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk")
            self.email = source_email
          end
        when "phone_number"
          self.phone_number = source_user.phone_number
        when "student_id"
          self.student_id = source_user.student_id
        when "associate_id"
          self.associate_id = source_user.associate_id
        when "avatar"
          if source_user.avatar.attached?
            avatar.purge if avatar.attached?
            avatar.attach(source_user.avatar.blob)
          end
        end
      end
      save! if changed?

      # Handle email for legacy behavior (unknown_ email replacement) when not explicitly chosen
      unless keep_from_source.include?("email")
        target_has_unknown = email.match?(/^unknown_.*@bedlamtheatre\.co\.uk$/)
        source_has_unknown = source_user.email.match?(/^unknown_.*@bedlamtheatre\.co\.uk$/)

        if target_has_unknown && !source_has_unknown
          source_email = source_user.email
          source_user.update_column(:email, "temp_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk")
          update!(email: source_email)
        end
      end

      # 1. Transfer TeamMembers (with duplicate handling)
      source_user.team_membership.each do |tm|
        existing = team_membership.find_by(teamwork_type: tm.teamwork_type, teamwork_id: tm.teamwork_id)
        if existing
          # Concatenate positions with '/' if they have different roles
          unless existing.position.include?(tm.position)
            existing.update!(position: "#{existing.position} / #{tm.position}")
          end
          tm.destroy!
        else
          tm.update!(user_id: id)
          transferred[:team_members] += 1
        end
      end

      # 2. Transfer Staffing Jobs
      transferred[:staffing_jobs] = source_user.staffing_jobs.update_all(user_id: id)

      # 3. Transfer Debts
      transferred[:maintenance_debts] = source_user.admin_maintenance_debts.update_all(user_id: id)
      transferred[:staffing_debts] = source_user.admin_staffing_debts.update_all(user_id: id)

      # 4. Transfer Debt Notifications
      transferred[:debt_notifications] = source_user.admin_debt_notifications.update_all(user_id: id)

      # 5. Transfer Maintenance Attendances
      transferred[:maintenance_attendances] = source_user.maintenance_attendances.update_all(user_id: id)

      # 6. Merge Roles (union)
      source_user.roles.each do |role|
        unless has_role?(role.name)
          add_role(role.name)
          transferred[:roles] << role.name
        end
      end

      # 7. Handle MembershipCard - keep target's, destroy source's
      source_user.membership_card&.destroy

      # 8. Handle MarketingCreatives::Profile - keep target's if exists, otherwise transfer
      if marketing_creatives_profile.nil? && source_user.marketing_creatives_profile.present?
        source_user.marketing_creatives_profile.update!(user_id: id)
      else
        source_user.marketing_creatives_profile&.destroy
      end

      # 9. Handle Avatar - keep target's if attached, otherwise transfer (unless explicitly chosen)
      unless keep_from_source.include?("avatar")
        if !avatar.attached? && source_user.avatar.attached?
          avatar.attach(source_user.avatar.blob)
        end
      end

      # 10. Reallocate debts after transfer to properly link jobs/attendances
      reallocate_maintenance_debts
      reallocate_staffing_debts

      # 11. Remove cached duplicate records involving source user
      CachedDuplicate.where(user1_id: source_user.id).or(CachedDuplicate.where(user2_id: source_user.id)).destroy_all

      # 12. Destroy source user - reload first to clear cached associations
      source_user.reload.destroy!
    end

    { success: true, transferred: transferred }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    { success: false, errors: [ e.message ] }
  end

  ##
  # Duplicate Detection
  ##

  # Returns the academic years the user was active based on their event participation.
  # Academic years run from September to August, so 2024-09-01 to 2025-08-31 is "2024/25".
  # Returns an array of starting years, e.g. [2022, 2023, 2024] for someone active in 22/23, 23/24, 24/25.
  def years_active
    event_dates = team_membership.where(teamwork_type: "Event")
                                 .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
                                 .pluck("events.start_date", "events.end_date")
    return [] if event_dates.empty?

    academic_years = Set.new
    event_dates.each do |start_date, end_date|
      next unless start_date && end_date
      # Convert dates to academic years (Sept-Aug) using the helper
      academic_years << ApplicationController.helpers.date_to_academic_year(start_date)
      academic_years << ApplicationController.helpers.date_to_academic_year(end_date)
    end
    academic_years.to_a.sort
  end

  # Check if this user's years of activity overlap with another user's
  # within the given threshold (default 4 years gap allowed).
  # Returns true if they overlap or if either has no activity data.
  # Optionally accepts a years_active_cache hash to avoid repeated DB queries.
  def years_overlap?(other_user, threshold: 4, years_active_cache: nil)
    my_years = years_active_cache ? years_active_cache[id] : years_active
    their_years = years_active_cache ? years_active_cache[other_user.id] : other_user.years_active
    my_years ||= []
    their_years ||= []
    return true if my_years.empty? || their_years.empty? # No data = assume possible match

    # Check if any year is within threshold of each other
    my_years.any? { |y| their_years.any? { |ty| (y - ty).abs <= threshold } }
  end

  # Bulk load years_active for multiple users in ONE query.
  # Returns a hash: { user_id => [year1, year2, ...], ... }
  def self.bulk_years_active_for(user_ids)
    return {} if user_ids.empty?

    # Single query to get all event dates for all users
    event_data = TeamMember.where(user_id: user_ids, teamwork_type: "Event")
                           .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
                           .pluck(:user_id, "events.start_date", "events.end_date")

    # Group by user_id and compute academic years
    result = Hash.new { |h, k| h[k] = Set.new }
    event_data.each do |user_id, start_date, end_date|
      next unless start_date && end_date
      result[user_id] << ApplicationController.helpers.date_to_academic_year(start_date)
      result[user_id] << ApplicationController.helpers.date_to_academic_year(end_date)
    end

    # Convert Sets to sorted Arrays
    result.transform_values { |years| years.to_a.sort }
  end

  # Mark another user as not a duplicate of this user
  def mark_not_duplicate(other_user)
    ids = not_duplicate_user_ids || []
    ids << other_user.id unless ids.include?(other_user.id)
    update!(not_duplicate_user_ids: ids)
  end

  # Check if this user has been marked as not a duplicate of another user (in either direction)
  def marked_not_duplicate?(other_user)
    (not_duplicate_user_ids || []).include?(other_user.id) ||
      (other_user.not_duplicate_user_ids || []).include?(id)
  end

  # Fuzzy first name matching using StringSimilarity module
  def self.fuzzy_first_name_match?(name1, name2, threshold: 0.6)
    StringSimilarity.fuzzy_name_match?(name1, name2, threshold: threshold)
  end

  def self.fuzzy_last_name_match?(last_name1, last_name2, threshold: 0.6)
    return false if last_name1.blank? || last_name2.blank?
    StringSimilarity.fuzzy_name_match?(last_name1, last_name2, threshold: threshold)
  end

  # Find all potential duplicate user pairs
  # Returns a hash with five buckets:
  #   - same_id: Users with same student_id or associate_id (definite duplicates)
  #   - fuzzy_name_overlapping: Last name exact + first name fuzzy + years overlap
  #   - fuzzy_name_non_overlapping: Last name exact + first name fuzzy + years don't overlap
  #   - fuzzy_both_overlapping: Both names fuzzy + years overlap (excludes exact last name matches)
  #   - fuzzy_both_no_overlap: Both names fuzzy + no years overlap (excludes exact last name matches)
  #
  # Performance optimized: Uses batch loading to minimize database queries.
  # Also returns years_active_cache for use in views to avoid re-querying.
  def self.find_potential_duplicates
    duplicates = {
      same_id: [],
      fuzzy_name_overlapping: [],
      fuzzy_name_non_overlapping: [],
      fuzzy_both_overlapping: [],
      fuzzy_both_no_overlap: []
    }

    # Use unscoped to avoid default ORDER BY conflicting with GROUP BY in MySQL
    # Bucket 1: Same student_id (definite duplicates regardless of years)
    duplicate_student_ids = unscoped.where.not(student_id: [ nil, "" ])
                                    .group(:student_id)
                                    .having("COUNT(*) > 1")
                                    .pluck(:student_id)
    if duplicate_student_ids.any?
      users_by_student_id = where(student_id: duplicate_student_ids).group_by(&:student_id)
      duplicate_student_ids.each do |sid|
        duplicates[:same_id] << { users: users_by_student_id[sid], match_type: :student_id, id_value: sid }
      end
    end

    # Bucket 1b: Same associate_id (definite duplicates regardless of years)
    duplicate_associate_ids = unscoped.where.not(associate_id: [ nil, "" ])
                                      .group(:associate_id)
                                      .having("COUNT(*) > 1")
                                      .pluck(:associate_id)
    if duplicate_associate_ids.any?
      users_by_associate_id = where(associate_id: duplicate_associate_ids).group_by(&:associate_id)
      duplicate_associate_ids.each do |aid|
        duplicates[:same_id] << { users: users_by_associate_id[aid], match_type: :associate_id, id_value: aid }
      end
    end

    # Bucket 2 & 3: Same last name with fuzzy first name match
    # Step 1: Get all last names that appear more than once
    duplicate_last_names = unscoped.where.not(last_name: [ nil, "" ])
                                   .group(:last_name)
                                   .having("COUNT(*) > 1")
                                   .pluck(:last_name)

    if duplicate_last_names.any?
      # Step 2: Batch-load ALL users with duplicate last names in ONE query
      all_users = where(last_name: duplicate_last_names).to_a
      users_by_last_name = all_users.group_by(&:last_name)

      # Step 3: Bulk-load years_active for all these users in ONE query
      all_user_ids = all_users.map(&:id)
      years_active_cache = bulk_years_active_for(all_user_ids)

      # Step 4: Process combinations using the cached data
      duplicate_last_names.each do |ln|
        users = users_by_last_name[ln]
        users.combination(2).each do |u1, u2|
          next if u1.marked_not_duplicate?(u2)
          next unless fuzzy_first_name_match?(u1.first_name, u2.first_name)

          if u1.years_overlap?(u2, years_active_cache: years_active_cache)
            duplicates[:fuzzy_name_overlapping] << { users: [ u1, u2 ], years_overlap: true, years_active_cache: years_active_cache }
          else
            duplicates[:fuzzy_name_non_overlapping] << { users: [ u1, u2 ], years_overlap: false, years_active_cache: years_active_cache }
          end
        end
      end
    end

    # Bucket 4 & 5: Loaded from cached_duplicates table by controller
    # (Background job computes these to avoid O(n²) performance issues)

    duplicates
  end

  ##
  # Roles
  # Overrides methods that only work on symbols to also work with the instance of the class.
  ##
  def add_role(role)
    if role.instance_of?(Symbol) || role.instance_of?(String)
      super(role)
    else
      super(role.name)
    end
  end

  def remove_role(role)
    if role.instance_of?(Symbol) || role.instance_of?(String)
      super(role)
    else
      super(role.name)
    end
  end

  def has_role?(role)
    if role.instance_of?(Symbol) || role.instance_of?(String)
      super(role)
    else
      super(role.name)
    end
  end

  def activate
    add_role :member
  end

  # If you change this, you must also update the scope.
  def consented?
    # Check if the user has consented less than a year ago.
    consented&.after?(Date.current.advance(years: -1))
  end

  def profile_complete?
    profile_completed_at.present?
  end

  def profile_incomplete?
    !profile_complete?
  end

  def complete_profile!
    update!(profile_completed_at: Time.current, consented: Date.current)
  end

  def profile_completion_token
    signed_id(purpose: :profile_completion, expires_in: 7.days)
  end

  def send_welcome_email
    UsersMailer.welcome_email(self).deliver_later unless email.ends_with?("@bedlamtheatre.co.uk")
  end

  private

  def extract_student_id_from_email
    return unless email.present?
    if email.match?(/\A(s\d{7})@ed\.ac\.uk\z/i)
      self.student_id = email.match(/\A(s\d{7})@ed\.ac\.uk\z/i)[1].downcase
    end
  end
end
