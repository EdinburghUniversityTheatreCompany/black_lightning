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
  has_many :membership_activation_tokens, class_name: "MembershipActivationToken", dependent: :destroy
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

  default_scope -> { order("last_name ASC") }

  # Also change the method 'consented'
  def self.not_consented
    where(consented: Date.current.advance(years: -100)..Date.current.advance(years: -1))
  end

  def self.by_first_name
    reorder("first_name ASC")
  end

  def self.ransackable_attributes(auth_object = nil)
    attributes = %w[first_name last_name full_name]
    attributes += %w[bio email public_profile] if auth_object.can?(:read, User)
    attributes += %w[activation_state consented email ever_activated phone_number username sign_in_count] if auth_object.can?(:manage, User)

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

  ransacker :full_name, formatter: proc { |v| v.mb_chars.downcase.to_s } do |parent|
    # Alternative
    # Arel.sql("CONCAT_WS(' ', users.first_name, users.last_name)")
    Arel::Nodes::NamedFunction.new("LOWER",
      [ Arel::Nodes::NamedFunction.new("concat_ws",
        [ Arel::Nodes::SqlLiteral.new("' '"), parent.table[:first_name], parent.table[:last_name] ]) ])
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
    debts = admin_maintenance_debts
      .where("due_by >= ? ", Date.current)
      .or(admin_maintenance_debts.where(maintenance_attendance: nil))
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
    debts = admin_staffing_debts
      .where("due_by >= ? ", Date.current)
      .or(admin_staffing_debts.where(admin_staffing_job: nil))
      .where(state: :normal)
      .order(due_by: :asc)
      .to_a

    # Find all jobs for this user that are currently not associated or associated with a debt (belonging to this user) already.
    jobs = staffing_jobs
      .includes(:staffing_debt)
      .where(admin_staffing_debts: { id: [ nil ] + debts.map(&:id) })
      .to_a

    # Filter out jobs that do not count towards debt
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

  def send_welcome_email
    UsersMailer.welcome_email(self).deliver_later unless email.ends_with?("@bedlamtheatre.co.uk")
  end
end
