# == Schema Information
#
# Table name: opportunities
# Database name: primary
#
#  id                :integer          not null, primary key
#  apply_url         :string(255)
#  approved          :boolean
#  author            :string(255)
#  compensation_type :integer          default(4), not null
#  contact_email     :string(255)
#  dates             :string(255)
#  description       :text(16777215)
#  email_visibility  :integer          default(0), not null
#  experience_level  :integer          default(0), not null
#  expiry_date       :date
#  location          :string(255)
#  project           :string(255)
#  submitter_email   :string(255)
#  submitter_name    :string(255)
#  title             :string(255)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  approver_id       :integer
#  company_id        :bigint
#  creator_id        :integer
#
# Indexes
#
#  index_opportunities_on_approved_and_expiry  (approved,expiry_date)
#  index_opportunities_on_approver_id          (approver_id)
#  index_opportunities_on_company_id           (company_id)
#  index_opportunities_on_creator_id           (creator_id)
#
# Foreign Keys
#
#  fk_rails_...  (company_id => companies.id)
#
class Opportunity < ApplicationRecord
  validates :title, length: { maximum: 255 }
  validates :description, length: { maximum: 16777215 }
  validates :contact_email, length: { maximum: 255 }
  validates :project, length: { maximum: 255 }
  validates :author, length: { maximum: 255 }
  validates :apply_url, length: { maximum: 255 }
  validates :submitter_name, length: { maximum: 255 }
  validates :submitter_email, length: { maximum: 255 }
  validates :dates, length: { maximum: 255 }
  validates :location, length: { maximum: 255 }
  # +website_url+ is the spam honeypot; +company_name+ is a virtual field resolved to a Company
  # before validation.
  attr_accessor :website_url
  attr_writer :company_name

  belongs_to :creator,  class_name: "User", optional: true
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :company, optional: true

  before_validation :assign_company_from_name
  after_destroy :cleanup_orphaned_company

  has_many :roles, class_name: "OpportunityRole", dependent: :destroy
  # Blank-position rows (an accidental "Add role") are dropped silently.
  accepts_nested_attributes_for :roles, allow_destroy: true, reject_if: ->(attrs) { attrs["position"].blank? }

  enum :email_visibility, { no_one: 0, members_only: 1, everyone: 2 }, default: :no_one, validate: true

  enum :compensation_type, {
    unpaid: 0,
    expenses_only: 1,
    paid: 2,
    profit_share: 3,
    tbc: 4
  }, default: :tbc, prefix: :compensation, validate: true

  enum :experience_level, {
    any: 0,
    student: 1,
    amateur: 2,
    professional: 3
  }, default: :any, prefix: :experience, validate: true

  validates :expiry_date, :description, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :submitter_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :creator_or_submitter
  validate :has_display_title

  normalizes :title, with: ->(title) { title&.strip }

  # If you update this, you must also update the active? method and the permission somewhere at the top of ability.rb.
  # You might also have to update the opportunities helper.
  scope :unexpired, -> { where("expiry_date > ?", Date.current) }
  scope :listable, -> { unexpired.where(approved: true) }
  scope :awaiting_review, -> { unexpired.where(approved: false) }
  scope :active, -> { listable.eutc_first }

  # EUTC companies first, then by expiry. Orders on opportunities columns only, so it stays valid
  # with SELECT DISTINCT (the department filter joins roles).
  scope :eutc_first, -> {
    reorder(Arel.sql("CASE WHEN opportunities.company_id IN (SELECT id FROM companies WHERE internal) THEN 0 ELSE 1 END, expiry_date ASC"))
  }

  def self.ransackable_attributes(auth_object = nil)
    [ "approved", "contact_email", "description", "email_visibility", "expiry_date", "title",
      "project", "author", "apply_url", "compensation_type", "experience_level", "company_id",
      "dates", "location" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "approver", "creator", "company", "roles" ]
  end

  def active?
    approved && !expired?
  end

  # Compares date-to-date: against Time.current an expiry_date coerces to midnight UTC, which in BST
  # keeps a closed posting "active" from 00:00 to 01:00.
  def expired?
    expiry_date <= Date.current
  end

  def external?
    creator_id.nil?
  end

  def on_behalf_of?
    creator_id.present? && submitter_name.present?
  end

  def attribution_label(viewer = nil, include_submitter_email: false)
    return submitter_name if external?
    return creator&.name(viewer) unless on_behalf_of?

    email = " (#{submitter_email})" if include_submitter_email && submitter_email.present?
    "#{creator&.name(viewer)}, on behalf of #{submitter_name}#{email}"
  end

  # An expiry_date of today already counts as past, so this drops it from the public listing.
  def close
    update(expiry_date: Date.current)
  end

  # Falls back to the company so the form pre-fills on edit.
  def company_name
    return @company_name if defined?(@company_name)

    company&.name
  end

  def display_title
    title.presence || [ company&.name, project ].compact_blank.join(": ").presence
  end

  # The label get_object_name and SimpleForm show for a title-less posting.
  def to_label
    display_title.presence || "Untitled opportunity"
  end

  def resolved_contact_email
    contact_email.presence || submitter_email.presence || creator&.email
  end

  # On-behalf postings notify the account creator who entered them, not the public contact_email
  # or the external submitter.
  def notification_email
    creator&.email || submitter_email.presence
  end

  # Mirrors notification_email's precedence so the salutation names the recipient.
  def notification_name
    creator&.name || submitter_name
  end

  # Prefers the submitter, mirroring resolved_contact_email, so name and email describe one person.
  def submitter_display_name(viewer = nil)
    submitter_name.presence || creator&.name(viewer)
  end

  def css_class
    return "" if expired?

    if active?
      "table-success"
    else
      "table-danger"
    end
  end

  private

  # Creates an unreviewed company if none matches; only when company_name was given.
  def assign_company_from_name
    return unless defined?(@company_name)

    name = @company_name.to_s.strip
    self.company = name.present? ? Company.find_or_build_by_name(name) : nil
  end

  # Removes a never-reviewed company left behind by a spam or rejected submission.
  def cleanup_orphaned_company
    return unless company&.reviewed == false
    company.destroy if company.opportunities.none? && company.events.none?
  end

  def creator_or_submitter
    return if creator_id.present?
    return if submitter_name.present? && submitter_email.present?

    errors.add(:base, "must have a creator or a submitter name and email")
  end

  def has_display_title
    return if display_title.present?

    errors.add(:base, "must have a title, or a company and project")
  end
end
