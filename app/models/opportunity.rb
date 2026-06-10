# == Schema Information
#
# Table name: opportunities
#
# *id*::               <tt>integer, not null, primary key</tt>
# *title*::            <tt>string(255)</tt>
# *description*::      <tt>text(16777215)</tt>
# *approved*::         <tt>boolean</tt>
# *creator_id*::       <tt>integer</tt>
# *approver_id*::      <tt>integer</tt>
# *expiry_date*::      <tt>date</tt>
# *email_visibility*:: <tt>integer, default(0), not null</tt>
# *contact_email*::    <tt>string(255)</tt>
# *company_id*::       <tt>bigint</tt>
# *project*::          <tt>string(255)</tt>
# *author*::           <tt>string(255)</tt>
# *apply_url*::        <tt>string(255)</tt>
# *submitter_name*::   <tt>string(255)</tt>
# *submitter_email*::  <tt>string(255)</tt>
# *compensation_type*::<tt>integer, default(4), not null</tt>
# *experience_level*:: <tt>integer, default(0), not null</tt>
# *dates*::            <tt>string(255)</tt>
# *location*::         <tt>string(255)</tt>
# *created_at*::       <tt>datetime, not null</tt>
# *updated_at*::       <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Opportunity < ApplicationRecord
  # +website_url+ is a spam honeypot. +company_name+ is a virtual field on both the admin and public
  # forms: it is resolved to a Company (created if it doesn't exist) by a before_validation hook.
  attr_accessor :website_url
  attr_writer :company_name

  belongs_to :creator,  class_name: "User", optional: true
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :company, optional: true

  before_validation :assign_company_from_name

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
  # not the public contact address, which may belong to someone else.
  def notification_email
    creator&.email || submitter_email.presence
  end

  # Human name of whoever posted this, account holder or external submitter.
  def submitter_display_name(viewer = nil)
    creator&.name(viewer) || submitter_name
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
