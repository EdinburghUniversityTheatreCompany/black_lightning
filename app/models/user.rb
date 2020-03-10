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
class User < ActiveRecord::Base
  before_save :unify_numbers
  rolify

  default_scope -> { order('last_name ASC') }

  def self.by_first_name
    unscoped.order('first_name ASC')
  end

  # Include default devise modules. Others available are:
  # :token_authenticatable, :confirmable,
  # :lockable, :timeoutable and :omniauthable
  # devise :ldap_authenticatable, :recoverable, :rememberable,
  #        :trackable, :registerable

  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  # set our own validations

  # Don't validate the password presence, so we can set it randomly for new users.
  # validates :password, :presence => true, :if => lambda { new_record? || !password.nil? || !password.blank? }
  validates :phone_number, allow_blank: true, format: { with: /\A(\(?\+?[0-9]*\)?)?[0-9_\- \(\)]*\z/, message: 'Please enter a valid mobile number' }

  has_one  :membership_card, dependent: :destroy
  delegate :card_number, to: :membership_card, allow_nil: true
  accepts_nested_attributes_for :membership_card, reject_if: :all_blank, allow_destroy: true

  has_many :team_membership, class_name: 'TeamMember'
  has_many :shows, through: :team_membership, source: :teamwork, source_type: 'Show'
  has_many :staffing_jobs, class_name: 'Admin::StaffingJob'
  has_many :staffings, through: :staffing_jobs, source: :staffable, source_type: 'Admin::Staffing'
  has_many :admin_maintenance_debts, class_name: 'Admin::MaintenanceDebt'
  has_many :admin_staffing_debts, class_name: 'Admin::StaffingDebt'
  has_many :admin_debt_notifications, class_name: 'Admin::DebtNotification'

  has_attached_file :avatar,
                    styles: { thumb: '150x150', display: '700x700' },
                    convert_options: { thumb: '-strip' }

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me, \
                  :first_name, :last_name, :role_ids, :phone_number, :card_number, \
                  :public_profile, :bio, :avatar, :username

  ##
  # A quick way of getting the user's full name.
  ##
  def name
    "#{first_name} #{last_name}"
  end

  ransacker :full_name do |parent|
    Arel::Nodes::NamedFunction.new('concat_ws', [Arel::Nodes.build_quoted(' '), parent.table[:first_name], parent.table[:last_name]])
  end

  ##
  # A quick way to get the user's full name, if they have a name, or their email
  ##
  def name_or_email
    name.presence || email
  end

  ##
  # Ensures that all phone numbers begin with +44 and don't have any spaces in.
  ##
  def unify_numbers
    return unless phone_number

    self.phone_number = phone_number.gsub(/\s/, '')

    if phone_number[0] == '0'
      phone_number[0] = '+44'
    end
  end

  ##
  # Creates a new user using the given params (e.g):
  #   User.create_user(params[:user])
  #
  # Generates a random password for the user if none is given.
  #
  # Will not save the new user.
  ##
  def self.create_user(params)
    user = User.new(params)

    unless user.password
      password_length = 6
      password = Devise.friendly_token.first(password_length)

      user.password = password
    end

    return user
  end

  # def ldap_before_save
  #   self.first_name = ldap_entry.givenName[0]
  #   self.last_name = ldap_entry.sn[0]
  #   self.email = ldap_entry.mail[0]
  # end

  # def after_ldap_authentication
  #   update_ldap_attributes
  # end

  # # Read LDAP attributes and roles, and map them to Black Lightning attributes
  # # and roles.
  # def update_ldap_attributes
  #   if ldap_entry
  #     puts "updating #{username}"
  #     self.first_name = ldap_entry.givenName[0]
  #     self.last_name = ldap_entry.sn[0]
  #     self.email = ldap_entry.mail[0]

  #     if ldap_entry.try(:telephoneNumber)
  #       self.phone_number = ldap_entry.telephoneNumber[0]
  #     end

  #     add_ldap_roles

  #     save!
  #   else
  #     puts "skipping #{name}"
  #   end
  # end

  # def add_ldap_roles
  #   ldap_group_names = ldap_groups.map { |dn| role_name_from_dn(dn) }

  #   self.roles = Role.where(name: ldap_group_names)
  # end

  # # For legacy reasons, some names are explicity mapped here:
  # # New roles should be added to IPA in lower case with hyphens (e.g. marketing-manager)
  # # and added to the website in title case (e.g Marketing Manager)
  # def role_name_from_dn(dn)
  #   group_name = dn.split(',')[0].gsub('cn=', '').gsub('-', ' ')

  #   case group_name
  #   when 'members'
  #     return 'member'
  #   when 'admins'
  #     return 'admin'
  #   when 'proposal viewer'
  #     return 'proposal_viewer'
  #   else
  #     group_name.titleize
  #   end
  # end

  # # Override Devise LDAP method, as it doesn't seem to work properly
  # def ldap_groups
  #   admin_ldap = Devise::LDAP::Connection.admin
  #   filter = Net::LDAP::Filter.eq('member', ldap_entry.dn)
  #   admin_ldap.search(filter: filter, base: 'cn=groups,cn=accounts,dc=bedlamtheatre,dc=co,dc=uk').collect(&:dn)
  # end

  ##
  # Returns true if the users first_name and last_name are set
  ##
  def has_basic_details?
    return !first_name.blank? && !last_name.blank?
  end

  def amount_of_maintenance_debts(on_date = Date.today)
    maintenance_debts = Admin::MaintenanceDebt.where(user: self).where('due_by <?', on_date).where.not(state: 'completed')
    return maintenance_debts.count {|debt| debt.status(on_date) == :causing_debt}
  end

  def amount_of_staffing_debts(on_date = Date.today)
    staffing_debts = Admin::StaffingDebt.where(user: self, admin_staffing_job_id: nil).where('due_by <?', on_date)
    return staffing_debts.count {|debt| debt.status(on_date) == :causing_debt}
  end

  def amount_of_unassociated_staffing_jobs(on_date = Date.today)
    # Returns the amount of staffing jobs that are not associated with any debt.
    return Admin::StaffingJob.where(user: self).joins("LEFT OUTER JOIN admin_staffing_debts ON admin_staffing_debts.admin_staffing_job_id = admin_staffing_jobs.id").where("admin_staffing_debts.admin_staffing_job_id IS null").count { |job| job.counts_towards_debt? }
  end

    #returns true if the user is in debt
  def in_debt(on_date = Date.today)
    return self.amount_of_maintenance_debts > 0 || self.amount_of_staffing_debts > 0
  end

  def self.in_debt(on_date = Date.today)
    in_debt_ids = self.find_each.map{ |user| user.in_debt(on_date) ? user.id : nil }
    return self.where(id: in_debt_ids)
  end


end
