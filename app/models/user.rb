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
  devise :database_authenticatable, :recoverable, :rememberable, \
         :trackable, :registerable # , :token_authenticatable

  # set our own validations

  # Don't validate the password presence, so we can set it randomly for new users.
  # validates :password, :presence => true, :if => lambda { new_record? || !password.nil? || !password.blank? }
  validates :email, presence: true, uniqueness: true
  validates :phone_number, allow_blank: true, format: { with: /(\+44\s?7\d{3}|07\d{3})\s?(\d{3}\s?\d{3})\z/, message: 'Please enter a valid mobile number' }

  has_one  :membership_card, dependent: :destroy
  delegate :card_number, to: :membership_card, allow_nil: true
  accepts_nested_attributes_for :membership_card, reject_if: :all_blank, allow_destroy: true

  has_many :team_membership, class_name: 'TeamMember'
  has_many :shows, through: :team_membership, source: :teamwork, source_type: 'Show'
  has_many :staffing_jobs, class_name: 'Admin::StaffingJob'
  has_many :staffings, through: :staffing_jobs, source: :staffable, source_type: 'Admin::Staffing'

  has_attached_file :avatar,
                    styles: { thumb: '150x150', display: '700x700' },
                    convert_options: { thumb: '-strip' }

  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me, \
                  :first_name, :last_name, :role_ids, :phone_number, :card_number, \
                  :public_profile, :bio, :avatar

  ##
  # A quick way of getting the user's full name.
  ##
  def name
    "#{first_name} #{last_name}"
  end

  ransacker :full_name do |parent|
    Arel::Nodes::NamedFunction.new('concat_ws', [' ', parent.table[:first_name], parent.table[:last_name]])
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

    reset_password = false

    unless user.password
      password_length = 6
      password = Devise.friendly_token.first(password_length)

      user.password = password
      user.reset_password_token = User.reset_password_token
      user.reset_password_sent_at = Time.now.utc

      reset_password = true
    end

    return user
  end

  ##
  # Returns true if the users first_name and last_name are set
  ##
  def has_basic_details?
    return !first_name.blank? && !last_name.blank?
  end
end
