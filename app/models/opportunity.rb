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
# *created_at*::       <tt>datetime, not null</tt>
# *updated_at*::       <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Opportunity < ApplicationRecord
  belongs_to :creator,  class_name: "User", optional: true
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :company, optional: true

  has_many :roles, class_name: "OpportunityRole", dependent: :destroy
  # A role is only meaningful with a position, so silently drop rows left blank (e.g. an
  # accidental "Add role" click) — the category select always has a default value, so
  # :all_blank would not catch them.
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
  scope :active, -> {
    listable
      .left_joins(:company)
      .order(Arel.sql("companies.internal DESC, expiry_date ASC"))
  }

  # Opportunities recruiting for a role in the given category, without joining roles
  # (avoids row multiplication, so it composes cleanly with ordering and Ransack).
  scope :with_role_category, ->(category) {
    where(id: OpportunityRole.where(category: category).select(:opportunity_id))
  }

  def self.ransackable_attributes(auth_object = nil)
    [ "approved", "contact_email", "description", "email_visibility", "expiry_date", "title",
      "project", "author", "apply_url", "compensation_type", "experience_level", "company_id" ]
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

  # Display heading for a posting: explicit title, else "Company: Project".
  def display_title
    title.presence || [ company&.name, project ].compact_blank.join(": ").presence
  end

  # Best email to reach the poster on, preferring an explicit contact address.
  def resolved_contact_email
    contact_email.presence || submitter_email.presence || creator&.email
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
