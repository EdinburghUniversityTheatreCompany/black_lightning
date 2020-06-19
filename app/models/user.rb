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
#--
# == Schema Information End
#++
##
class User < ApplicationRecord
  before_save :unify_numbers
  rolify

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
  # devise :ldap_authenticatable, :recoverable, :rememberable,
  #        :trackable, :registerable

  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  # set our own validations
  validates :phone_number, allow_blank: true, format: { with: /\A(\(?\+?[0-9]*\)?)?[0-9_\- \(\)]*\z/, message: 'Please enter a valid mobile number' }
  validates :email, presence: true

  validates :avatar, content_type: %i[png jpg jpeg gif]

  has_one  :membership_card, dependent: :destroy
  delegate :card_number, to: :membership_card, allow_nil: true
  accepts_nested_attributes_for :membership_card, reject_if: :all_blank, allow_destroy: true

  has_many :team_membership, class_name: 'TeamMember', dependent: :restrict_with_error 
  has_many :shows, through: :team_membership, source: :teamwork, source_type: 'Show'
  has_many :staffing_jobs, class_name: 'Admin::StaffingJob', dependent: :restrict_with_error 
  has_many :staffings, through: :staffing_jobs, source: :staffable, source_type: 'Admin::Staffing'
  has_many :admin_maintenance_debts, class_name: 'Admin::MaintenanceDebt', dependent: :restrict_with_error 
  has_many :admin_staffing_debts, class_name: 'Admin::StaffingDebt', dependent: :restrict_with_error 
  has_many :admin_debt_notifications, class_name: 'Admin::DebtNotification', dependent: :destroy
  has_many :membership_activation_tokens, class_name: 'MembershipActivationToken', dependent: :destroy

  has_one_attached :avatar

  default_scope -> { order('last_name ASC') }

  def self.by_first_name
    reorder('first_name ASC')
  end

  def ability
    @ability ||= Ability.new(self)
  end

  delegate :can?, :cannot?, to: :ability

  # Returns true if the users first_name and last_name are set.
  def name?
    return first_name.present? && last_name.present?
  end

  # A quick way of getting the user's full name.
  def name_or_default
    return "#{first_name} #{last_name}" if name?

    return 'No Name Set'
  end

  # A quick way to get the user's full name, if they have a name, or their email.
  # Does not check for permissions.
  def name_or_email
    return name_or_default if name?

    return email
  end

  # Returns the name if present, and the email if the user has the permission.
  # Can also be the current_ability instead of the current_user.
  def name(current_user = nil)
    if current_user.present? && current_user.can?(:show, self)
      return name_or_email
    else
      return name_or_default
    end
  end

  # Ensures that all phone numbers begin with +44 and don't have any spaces in.
  def unify_numbers
    return unless phone_number

    self.phone_number = phone_number.gsub(/\s/, '')

    if phone_number[0] == '0'
      phone_number[0] = '+44'
    end
  end

  ransacker :full_name do |parent|
    Arel::Nodes::NamedFunction.new('concat_ws', [Arel::Nodes.build_quoted(' '), parent.table[:first_name], parent.table[:last_name]])
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

    return user
  end

  # The current and upcoming function share code, so please check them both if you change things.
  def debt_causing_maintenance_debts(on_date = Date.today)
    return Admin::MaintenanceDebt.where(user: self).where('due_by < ?', on_date).unfulfilled
  end

  def upcoming_maintenance_debts(from_date = Date.today)
    return Admin::MaintenanceDebt.where(user: self).where('due_by >= ?', from_date).unfulfilled
  end
  
  def debt_causing_staffing_debts(on_date = Date.today)
    return Admin::StaffingDebt.where(user: self, admin_staffing_job_id: nil).where('due_by < ?', on_date).where(admin_staffing_job: nil, forgiven: false)
  end

  def upcoming_staffing_debts(from_date = Date.today)
    return Admin::StaffingDebt.where(user: self, admin_staffing_job_id: nil).where('due_by >= ?', from_date).where(admin_staffing_job: nil, forgiven: false)
  end

  def debt_message_suffix(on_date = Date.today)
    in_maintenance_debt = debt_causing_maintenance_debts(on_date).any?
    in_staffing_debt = debt_causing_staffing_debts(on_date).any?

    if in_maintenance_debt && in_staffing_debt
      return 'in staffing and maintenance Debt'
    elsif in_maintenance_debt
      return 'in maintenance Debt'
    elsif in_staffing_debt
      return 'in staffing Debt'
    else
      return 'not in Debt'
    end
  end

  # Returns true if the user is in debt
  # Rename to in debt?
  def in_debt(on_date = Date.today)
    return debt_causing_maintenance_debts(on_date).any? || debt_causing_staffing_debts(on_date).any?
  end

  def self.in_debt(on_date = Date.today)
    in_debt_ids = find_each.map { |user| user.in_debt(on_date) ? user.id : nil }
    return where(id: in_debt_ids)
  end

  # returns users who have been sent a notification since the given date
  def self.notified_since(date)
    return includes(:admin_debt_notifications).where('admin_debt_notifications.sent_on > ?', date).references(:admin_debt_notifications).distinct
  end

  # Note: This function does not have any regard for permissions.
  def team_memberships(public_only)
    team_memberships = team_membership.where(teamwork_type: 'Event')
    team_memberships = team_memberships.select { |team_member| team_member.teamwork&.is_public } if public_only
    return team_memberships.sort { |a, b| a.teamwork.start_date <=> b.teamwork.start_date }
  end
end
