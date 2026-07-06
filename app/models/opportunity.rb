# == Schema Information
#
# Table name: opportunities
# Database name: primary
#
#  id                :integer          not null, primary key
#  apply_url         :string(255)
#  approved          :boolean
#  author            :string(255)
#  compensation_type :integer          default("tbc"), not null
#  contact_email     :string(255)
#  dates             :string(255)
#  description       :text(16777215)
#  email_visibility  :integer          default("no_one"), not null
#  experience_level  :integer          default("any"), not null
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
  # Length validations enforcing database column limits
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
  # +website_url+ is a spam honeypot. +company_name+ is a virtual field on both the admin and public
  # forms: it is resolved to a Company (created if it doesn't exist) by a before_validation hook.
  attr_accessor :website_url
  attr_writer :company_name

  belongs_to :creator,  class_name: "User", optional: true
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :company, optional: true

  before_validation :assign_company_from_name
  after_destroy :cleanup_orphaned_company

  has_many :roles, class_name: "OpportunityRole", dependent: :destroy
  # A role is only meaningful with a position, so silently drop rows left blank (e.g. an
  # accidental "Add role" click).
  accepts_nested_attributes_for :roles, allow_destroy: true, reject_if: ->(attrs) { attrs["position"].blank? }

  enum :email_visibility, { no_one: 0, members_only: 1, everyone: 2 }, default: :no_one

  enum :compensation_type, {
    unpaid: 0,
    expenses_only: 1,
    paid: 2,
    profit_share: 3,
    tbc: 4
  }, default: :tbc, prefix: :compensation

  enum :experience_level, {
    any: 0,
    student: 1,
    amateur: 2,
    professional: 3
  }, default: :any, prefix: :experience

  validates :expiry_date, :description, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :submitter_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :creator_or_submitter
  validate :has_display_title

  normalizes :title, with: ->(title) { title&.strip }

  # If you update this, you must also update the active? method and the permission somewhere at the top of ability.rb.
  # You might also have to update the opportunities helper.
  # +listable+ is the unordered "publicly visible" set, used as a base for filtering/sorting
  # (e.g. the public listing applies Ransack on top). +active+ adds the internal-first ordering.
  scope :listable, -> { where("approved = true AND expiry_date > ?", Time.current) }
  scope :active, -> { listable.eutc_first }

  # EUTC (internal) opportunities first, then by expiry. Orders by a CASE on the opportunities
  # table only (no companies join), so it stays valid alongside SELECT DISTINCT — needed because
  # filtering by role department joins the roles has-many.
  scope :eutc_first, -> {
    ids = Company.where(internal: true).ids
    return reorder("expiry_date ASC") if ids.empty?

    reorder(Arel.sql("CASE WHEN opportunities.company_id IN (#{ids.join(',')}) THEN 0 ELSE 1 END, expiry_date ASC"))
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
    approved && expiry_date > Time.current
  end

  # An opportunity submitted by someone without a user account (a public/external submission).
  def external?
    creator_id.nil?
  end

  # An opportunity entered by a user (the creator) on behalf of an external submitter, so the
  # display can credit both instead of implying the external person created it themselves.
  def on_behalf_of?
    creator_id.present? && submitter_name.present?
  end

  # Immediately expire the posting so it drops out of the public listing. The column is a date,
  # so today's date already compares as past against Time.current.
  def close
    update(expiry_date: Date.current)
  end

  # The typed company name, falling back to the associated company so the form pre-fills on edit.
  def company_name
    return @company_name if defined?(@company_name)

    company&.name
  end

  # Display heading for a posting: explicit title, else "Company: Project".
  def display_title
    title.presence || [ company&.name, project ].compact_blank.join(": ").presence
  end

  # Used by get_object_name / SimpleForm so title-less postings still show a sensible label.
  def to_label
    display_title.presence || "Untitled opportunity"
  end

  # Best email to reach the poster on, preferring an explicit contact address.
  def resolved_contact_email
    contact_email.presence || submitter_email.presence || creator&.email
  end

  # Where to send submission notifications (approval/rejection): the submitter themselves,
  # not the public contact address, which may belong to someone else. Prefer the external
  # submitter so on-behalf postings notify the person the posting is for, not who typed it in.
  def notification_email
    submitter_email.presence || creator&.email
  end

  # Name of the notification recipient, mirroring notification_email's submitter-first precedence
  # so the salutation always matches whoever the email is actually addressed to.
  def notification_name
    submitter_name.presence || creator&.name
  end

  # Human name of whoever posted this. Prefer the external submitter, mirroring
  # resolved_contact_email, so the displayed name and email always describe the same person.
  def submitter_display_name(viewer = nil)
    submitter_name.presence || creator&.name(viewer)
  end

  def css_class
    return "" unless expiry_date > Time.current

    if active?
      "table-success".html_safe
    else
      "table-danger".html_safe
    end
  end

  private

  # Resolve the typed company name to a Company (creating an unreviewed one if it doesn't exist).
  # Only runs when company_name was explicitly provided on this save (admin or public form).
  def assign_company_from_name
    return unless defined?(@company_name)

    name = @company_name.to_s.strip
    self.company = name.present? ? Company.find_or_build_by_name(name) : nil
  end

  # When an opportunity is destroyed, remove its company if it was never reviewed and now has
  # no other opportunities — prevents orphaned company records from spam/rejected submissions.
  def cleanup_orphaned_company
    return unless company&.reviewed == false
    company.destroy if company.opportunities.none? && company.events.none?
  end

  # A posting must be attributable to either a logged-in creator or a named external submitter.
  def creator_or_submitter
    return if creator_id.present?
    return if submitter_name.present? && submitter_email.present?

    errors.add(:base, "must have a creator or a submitter name and email")
  end

  # Title is optional, but a posting must still produce a heading from a title or a company/project.
  def has_display_title
    return if display_title.present?

    errors.add(:base, "must have a title, or a company and project")
  end
end
