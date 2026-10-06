##
# Model used by Devise for users.
#
# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                         :integer          not null, primary key
#  avatar_content_type        :string(255)
#  avatar_file_name           :string(255)
#  avatar_file_size           :integer
#  avatar_updated_at          :datetime
#  bio                        :text(16777215)
#  calendar_email             :string(255)
#  calendar_token             :string(255)
#  consented                  :date
#  current_sign_in_at         :datetime
#  current_sign_in_ip         :string(255)
#  email                      :string(255)      default(""), not null
#  encrypted_password         :string(255)      default(""), not null
#  first_name                 :string(255)
#  last_name                  :string(255)
#  last_sign_in_at            :datetime
#  last_sign_in_ip            :string(255)
#  not_duplicate_user_ids     :json
#  phone_number               :string(255)
#  pretix_customer_identifier :string(190)
#  profile_completed_at       :datetime
#  profile_completion_salt    :string(255)
#  public_profile             :boolean          default(TRUE)
#  remember_created_at        :datetime
#  remember_token             :string(255)
#  reset_password_sent_at     :datetime
#  reset_password_token       :string(255)
#  sign_in_count              :integer          default(0)
#  username                   :string(255)
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  airtable_person_id         :string(255)
#  associate_id               :string(255)
#  reimbursements_person_id   :bigint
#  student_id                 :string(255)
#
# Indexes
#
#  index_users_on_associate_id                (associate_id)
#  index_users_on_calendar_token              (calendar_token) UNIQUE
#  index_users_on_email                       (email) UNIQUE
#  index_users_on_last_name                   (last_name)
#  index_users_on_pretix_customer_identifier  (pretix_customer_identifier) UNIQUE
#  index_users_on_profile_completed_at        (profile_completed_at)
#  index_users_on_reimbursements_person_id    (reimbursements_person_id)
#  index_users_on_reset_password_token        (reset_password_token) UNIQUE
#  index_users_on_student_id                  (student_id)
#
# Foreign Keys
#
#  fk_rails_...  (reimbursements_person_id => reimbursements_people.id)
#
class User < ApplicationRecord
  validates :email, :encrypted_password, :reset_password_token, :current_sign_in_ip, :last_sign_in_ip,
            :first_name, :last_name, :phone_number, :avatar_file_name, :avatar_content_type, :username,
            :remember_token, :student_id, :associate_id, :calendar_token, :calendar_email,
            :profile_completion_salt, length: { maximum: 255 }
  validates :bio, length: { maximum: 16777215 }
  before_save :unify_numbers
  before_save :ensure_profile_completion_salt
  before_validation :extract_student_id_from_email, if: :email_changed?

  rolify
  has_paper_trail

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
  has_secure_token :calendar_token

  # set our own validations
  validates :phone_number, allow_blank: true, format: { with: /\A(\(?\+?[0-9]*\)?)?[0-9_\- \(\)]*\z/, message: "Please enter a valid mobile number" }
  validates :email, presence: true
  validates :calendar_email, allow_blank: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }

  validates :avatar, content_type: %i[png jpg jpeg gif webp]
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

  # The linked reimbursements payee. airtable_person_id is import provenance, never written.
  belongs_to :reimbursements_person, class_name: "Reimbursements::Person",
             optional: true, inverse_of: :user

  # An erasure request is served by deleting the account, so this must reach the linked payee's
  # bank details (the association above only nullifies). The payee and its claims stay as
  # financial records.
  before_destroy :erase_reimbursements_bank_details

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
  has_many :maintenance_credits, class_name: "MaintenanceCredit", dependent: :restrict_with_error

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

  scope :order_by_last_name_first, -> { order(:last_name, :first_name) }
  scope :search_by_name, ->(q) { where("CONCAT(first_name, ' ', last_name) LIKE ?", "%#{q}%") }

  # Also change the method 'consented'
  def self.not_consented
    where(consented: Date.current.advance(years: -100)..Date.current.advance(years: -1))
  end

  def self.find_by_profile_completion_token(token)
    where(profile_completed_at: nil).each do |user|
      found = find_signed(token, purpose: [ :profile_completion, user.profile_completion_salt ])
      return found if found && found == user
    end

    nil
  rescue StandardError
    nil
  end

  def self.ransackable_attributes(auth_object = nil)
    attributes = %w[first_name last_name full_name]
    attributes += %w[bio email public_profile student_id associate_id member_id] if auth_object.can?(:read, User)
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

  def calendar_email_for_invites
    calendar_email.presence || email
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
      "in staffing and maintenance debt"
    elsif in_maintenance_debt
      "in maintenance debt"
    elsif in_staffing_debt
      "in staffing debt"
    else
      "not in debt"
    end
  end

  # Returns true if the user is in debt
  # Rename to in debt?
  def in_debt(on_date = Date.current)
    debt_causing_maintenance_debts(on_date).any? || debt_causing_staffing_debts(on_date).any?
  end

  def self.in_debt(on_date = Date.current)
    where(id: Admin::MaintenanceDebt.unfulfilled_before_date(on_date).select(:user_id))
      .or(where(id: Admin::StaffingDebt.unfulfilled_before_date(on_date).select(:user_id)))
      .distinct
  end

  # returns users who have been sent a notification since the given date
  def self.notified_since(date)
    includes(:admin_debt_notifications).where("admin_debt_notifications.sent_on > ?", date).references(:admin_debt_notifications).distinct
  end

  # Note: This function does not have any regard for permissions.
  def team_memberships(public_only)
    query = team_membership.where(teamwork_type: "Event")
                          .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
                          .preload(teamwork: [ :venue, :season, { image_attachment: :blob } ])

    results = query.to_a

    if public_only
      results = results.select { |tm| tm.teamwork.is_public }
    end

    results.sort_by { |tm| tm.teamwork.start_date || Date.current }
  end

  # Set while a MaintenanceSession persists a batch of credits, so each user reallocates once
  # rather than once per credit (MaintenanceSession#reallocate_attendee_debts_once).
  thread_mattr_accessor :suppress_maintenance_reallocation, instance_accessor: false

  # Pairs the soonest reallocatable debts with credits and unlinks the rest.
  def reallocate_maintenance_debts
    return if self.class.suppress_maintenance_reallocation

    debts = reallocatable(admin_maintenance_debts, :maintenance_credit)
    credits = maintenance_credits
              .includes(:maintenance_debt)
              .where(admin_maintenance_debts: { id: [ nil ] + debts.map(&:id) })
              .to_a
    pair_debts(debts, credits, :maintenance_credit)
  end

  # Pairs the soonest reallocatable debts with staffing jobs and unlinks the rest.
  def reallocate_staffing_debts
    debts = reallocatable(admin_staffing_debts, :admin_staffing_job)
    jobs = staffing_jobs
           .includes(:staffing_debt)
           .where(admin_staffing_debts: { id: [ nil ] + debts.map(&:id) })
           # counts_towards_debt? cannot be eager loaded (polymorphic staffable), so this runs per job.
           .select(&:counts_towards_debt?)
    pair_debts(debts, jobs, :admin_staffing_job)
  end

  ##
  # Merging Users
  ##

  def staffing_jobs_unlinked_count
    staffing_jobs.left_joins(:staffing_debt).where(admin_staffing_debts: { id: nil }).count
  end

  def staffing_debts_unlinked_count
    admin_staffing_debts.where(admin_staffing_job_id: nil, state: :normal).count
  end

  def maintenance_debts_unlinked_count
    admin_maintenance_debts.where(maintenance_credit_id: nil, state: :normal).count
  end

  def maintenance_credits_unlinked_count
    maintenance_credits.left_joins(:maintenance_debt).where(admin_maintenance_debts: { id: nil }).count
  end

  def overlapping_team_memberships_with(other_user)
    team_membership.where(
      teamwork_type: other_user.team_membership.select(:teamwork_type),
      teamwork_id: other_user.team_membership.select(:teamwork_id)
    ).count
  end

  # Counts for the merge preview modal.
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
      maintenance_credits: {
        total: maintenance_credits.count,
        unlinked: maintenance_credits_unlinked_count
      },
      roles: roles.pluck(:name)
    }
  end

  KEEPABLE_FIELDS = {
    "name" => %i[first_name last_name], "email" => %i[email], "phone_number" => %i[phone_number],
    "student_id" => %i[student_id], "associate_id" => %i[associate_id]
  }.freeze

  # Merges source_user into this user and destroys it. keep_from_source names the fields to copy
  # from the source (name, email, phone_number, student_id, associate_id, avatar).
  # Returns { success:, errors:, transferred: }.
  def absorb(source_user, keep_from_source: [])
    return { success: false, errors: [ "Cannot merge user into itself" ] } if source_user&.id == id
    return { success: false, errors: [ "Source user not found" ] } if source_user.nil?

    transferred = {
      team_members: 0,
      staffing_jobs: 0,
      maintenance_debts: 0,
      staffing_debts: 0,
      debt_notifications: 0,
      maintenance_credits: 0,
      roles: []
    }

    ActiveRecord::Base.transaction do
      park_source_email = -> { source_user.update_column(:email, "temp_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk") }

      keep_from_source.each do |field|
        KEEPABLE_FIELDS.fetch(field.to_s, []).each { |attr| public_send("#{attr}=", source_user.public_send(attr)) }
      end
      # Taking the source's email, or one that normalises to ours (sms.ed.ac.uk vs ed.ac.uk),
      # would fail uniqueness on save, so move it aside first.
      park_source_email.call if keep_from_source.include?("email") || source_user.email == email
      save! if changed?

      # Replace our unknown_ placeholder email with the source's real one.
      unless keep_from_source.include?("email")
        target_has_unknown = email.match?(/^unknown_.*@bedlamtheatre\.co\.uk$/)
        source_has_unknown = source_user.email.match?(/^unknown_.*@bedlamtheatre\.co\.uk$/)

        if target_has_unknown && !source_has_unknown
          source_email = source_user.email
          # Skip when a third user already holds the normalised email.
          unless User.where.not(id: [ id, source_user.id ]).exists?(email: source_email)
            park_source_email.call
            update!(email: source_email)
          end
        end
      end

      source_user.team_membership.each do |tm|
        existing = team_membership.find_by(teamwork_type: tm.teamwork_type, teamwork_id: tm.teamwork_id)
        if existing
          unless existing.position.include?(tm.position)
            existing.update!(position: "#{existing.position} / #{tm.position}")
          end
          tm.destroy!
        else
          tm.update!(user_id: id)
          transferred[:team_members] += 1
        end
      end

      transferred[:staffing_jobs] = source_user.staffing_jobs.update_all(user_id: id)

      transferred[:maintenance_debts] = source_user.admin_maintenance_debts.update_all(user_id: id)
      transferred[:staffing_debts] = source_user.admin_staffing_debts.update_all(user_id: id)

      transferred[:debt_notifications] = source_user.admin_debt_notifications.update_all(user_id: id)

      transferred[:maintenance_credits] = source_user.maintenance_credits.update_all(user_id: id)

      source_user.roles.each do |role|
        # Never absorb Admin. Stopping non-admins absorbing admins belongs in CanCanCan.
        next if role.name == "Admin"
        unless has_role?(role.name)
          add_role(role.name)
          transferred[:roles] << role.name
        end
      end

      if marketing_creatives_profile.nil? && source_user.marketing_creatives_profile.present?
        source_user.marketing_creatives_profile.update!(user_id: id)
      else
        source_user.marketing_creatives_profile&.destroy
      end

      if source_user.avatar.attached? && (keep_from_source.include?("avatar") || !avatar.attached?)
        avatar.attach(source_user.avatar.blob)
      end

      reallocate_maintenance_debts
      reallocate_staffing_debts

      CachedDuplicate.where(user1_id: source_user.id).or(CachedDuplicate.where(user2_id: source_user.id)).destroy_all

      # Reload to drop the associations that were just moved.
      source_user.reload.destroy!
    end

    { success: true, transferred: transferred }
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    { success: false, errors: [ e.message ] }
  end

  ##
  # Duplicate Detection
  ##

  def years_active = self.class.bulk_years_active_for([ id ]).fetch(id, [])

  # True when a year of ours is within 4 years of one of theirs. years_active_cache avoids
  # repeated queries.
  def years_overlap?(other_user, years_active_cache: nil)
    my_years = years_active_cache ? years_active_cache[id] : years_active
    their_years = years_active_cache ? years_active_cache[other_user.id] : other_user.years_active
    my_years ||= []
    their_years ||= []
    return true if my_years.empty? || their_years.empty? # No data = assume possible match

    my_years.any? { |y| their_years.any? { |ty| (y - ty).abs <= 4 } }
  end

  # Starting years of the academic years (September to August) in which each user had an event,
  # e.g. [2022, 2023] for 22/23 and 23/24: { user_id => [year, ...] }, in one query.
  def self.bulk_years_active_for(user_ids)
    return {} if user_ids.empty?

    event_data = TeamMember.where(user_id: user_ids, teamwork_type: "Event")
                           .joins("INNER JOIN events ON events.id = team_members.teamwork_id")
                           .pluck(:user_id, "events.start_date", "events.end_date")

    result = Hash.new { |h, k| h[k] = Set.new }
    event_data.each do |user_id, start_date, end_date|
      next unless start_date && end_date
      result[user_id] << ApplicationController.helpers.date_to_academic_year(start_date)
      result[user_id] << ApplicationController.helpers.date_to_academic_year(end_date)
    end

    result.transform_values { |years| years.to_a.sort }
  end

  def mark_not_duplicate(other_user)
    ids = not_duplicate_user_ids || []
    ids << other_user.id unless ids.include?(other_user.id)
    update!(not_duplicate_user_ids: ids)
  end

  # The mark may be on either user.
  def marked_not_duplicate?(other_user)
    (not_duplicate_user_ids || []).include?(other_user.id) ||
      (other_user.not_duplicate_user_ids || []).include?(id)
  end

  def self.fuzzy_first_name_match?(name1, name2, threshold: 0.6)
    StringSimilarity.fuzzy_name_match?(name1, name2, threshold: threshold)
  end

  # Potential duplicate pairs, in three buckets:
  #   same_id: same student_id, associate_id or equivalent sms email (definite duplicates)
  #   fuzzy_name_overlapping / fuzzy_name_non_overlapping: same last name, fuzzy first name,
  #     split by whether their years of activity overlap
  # The fuzzy_both buckets (fuzzy on both names) come from cached_duplicates, which
  # RefreshFuzzyBothDuplicatesJob fills because that scan is O(n²); Admin::DuplicatesController sets them.
  # Each fuzzy pair carries years_active_cache so views need not re-query.
  def self.find_potential_duplicates
    duplicates = { same_id: [], fuzzy_name_overlapping: [], fuzzy_name_non_overlapping: [] }

    %i[student_id associate_id].each do |column|
      values = shared_values(column)
      users_by_value = where(column => values).group_by(&column)
      values.each do |value|
        duplicates[:same_id] << { users: users_by_value[value], match_type: column, id_value: value }
      end
    end

    # s1234567@sms.ed.ac.uk is s1234567@ed.ac.uk: legacy records predate the normalisation.
    sms_email_users = unscoped.where("email LIKE ?", "%@sms.ed.ac.uk").to_a
    sms_email_users.each do |sms_user|
      normalized_email = sms_user.email.sub("@sms.ed.ac.uk", "@ed.ac.uk")
      counterpart = find_by(email: normalized_email)
      next unless counterpart
      next if sms_user.marked_not_duplicate?(counterpart)
      duplicates[:same_id] << { users: [ sms_user, counterpart ], match_type: :email, id_value: normalized_email }
    end

    duplicate_last_names = shared_values(:last_name)

    if duplicate_last_names.any?
      all_users = where(last_name: duplicate_last_names).to_a
      users_by_last_name = all_users.group_by(&:last_name)

      all_user_ids = all_users.map(&:id)
      years_active_cache = bulk_years_active_for(all_user_ids)

      duplicate_last_names.each do |ln|
        users = users_by_last_name[ln]
        users.combination(2).each do |u1, u2|
          next if u1.marked_not_duplicate?(u2)
          next unless fuzzy_first_name_match?(u1.first_name, u2.first_name)

          bucket = u1.years_overlap?(u2, years_active_cache: years_active_cache) ? :fuzzy_name_overlapping : :fuzzy_name_non_overlapping
          duplicates[bucket] << { users: [ u1, u2 ], years_active_cache: years_active_cache }
        end
      end
    end

    duplicates
  end

  # unscoped: the default ORDER BY clashes with GROUP BY in MySQL.
  private_class_method def self.shared_values(column)
    unscoped.where.not(column => [ nil, "" ]).group(column).having("COUNT(*) > 1").pluck(column)
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

  # Facts read from the role, NOT permissions: they drive mailing lists, the membership report and
  # the annual archive, so a grid checkbox on another role must not make its holders members.
  # A life member is not a member here; only pretix treats them as one
  # (Pretix::MembershipSync::ENTITLING_ROLES).
  def member?
    has_role?(:member)
  end

  def committee?
    has_role?("Committee")
  end

  # Admin is the one role Ability reads directly (can :manage, :all); everything else is the grid.
  def admin?
    has_role?("Admin")
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
    # Reset salt to invalidate any existing tokens
    update!(profile_completed_at: Time.current, consented: Date.current, profile_completion_salt: SecureRandom.hex(8))
  end

  def profile_completion_token
    signed_id(purpose: [ :profile_completion, profile_completion_salt ], expires_in: 7.days)
  end

  def send_welcome_email
    UsersMailer.welcome_email(self).deliver_later unless email.ends_with?("@bedlamtheatre.co.uk")
  end

  def ensure_calendar_token!
    return if calendar_token.present?
    update_column(:calendar_token, SecureRandom.base58(24))
  end

  private

  # Future debts, plus past ones still unfulfilled, soonest first.
  def reallocatable(debts, link)
    debts.includes(link).where("due_by >= ?", Date.current)
         .or(debts.includes(link).where(link => nil))
         .where(state: :normal).order(due_by: :asc).to_a
  end

  # The i-th debt takes the i-th fulfilment; debts past the last one are unlinked.
  def pair_debts(debts, fulfilments, link)
    ActiveRecord::Base.transaction do
      debts.each_with_index do |debt, i|
        next if debt.public_send(link) == fulfilments[i]

        debt.class.where(id: debt.id).update_all("#{link}_id" => fulfilments[i]&.id)
      end
    end
  end

  # PersonLink resolves a payee by the stored link, then by email, so erasure must follow both.
  def erase_reimbursements_bank_details
    person = reimbursements_person ||
             Reimbursements::Person.find_by(email: email.to_s.presence)
    person&.payment_details&.destroy!
  end

  def ensure_profile_completion_salt
    self.profile_completion_salt ||= SecureRandom.hex(8)
  end

  def extract_student_id_from_email
    return unless email.present?
    if email.match?(/\A(s\d{7})@ed\.ac\.uk\z/i)
      self.student_id = email.match(/\A(s\d{7})@ed\.ac\.uk\z/i)[1].downcase
    end
  end
end
