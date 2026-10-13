##
# Represents a job/position that may need to be staffed.
#
# == Schema Information
#
# Table name: admin_staffing_jobs
# Database name: primary
#
#  id                :integer          not null, primary key
#  calendar_sequence :integer          default(0), not null
#  name              :string(255)
#  reminder_sent_at  :datetime
#  staffable_type    :string(255)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  staffable_id      :integer
#  user_id           :integer
#
# Indexes
#
#  index_admin_staffing_jobs_on_reminder_sent_at  (reminder_sent_at)
#  index_admin_staffing_jobs_on_staffable         (staffable_type,staffable_id)
#  index_admin_staffing_jobs_on_staffable_type    (staffable_type)
#  index_admin_staffing_jobs_on_user_id           (user_id)
#
class Admin::StaffingJob < ApplicationRecord
  validates :name, :staffable_type, length: { maximum: 255 }
  validates :name, presence: true

  scope :pending_reminder, -> { where(reminder_sent_at: nil).where.not(user: nil) }

  belongs_to :staffable, polymorphic: true
  belongs_to :user, optional: true
  has_one :staffing_debt, class_name: "Admin::StaffingDebt", foreign_key: "admin_staffing_job_id"

  after_save :send_calendar_invite_email # before associate_with_debt, whose reload clears saved_changes
  after_save :associate_with_debt
  after_destroy :send_calendar_cancellation_email
  after_destroy :dissassociate_from_debt

  has_paper_trail

  normalizes :name, with: ->(name) { name&.strip }

  # The functions that use staffable don't check if it's a staffing instead of a template.
  # They should just hard-fail when the staffable is a template. That situation should simply not occur.

  def completed?
    staffable.end_time < DateTime.current
  end

  def counts_towards_debt?
    staffable.present? && staffable.counts_towards_debt? && name.downcase != "committee rep"
  end

  # Returns the staffing jobs that are not associated with any debt and count towards staffing.
  def self.unassociated_staffing_jobs_that_count_towards_debt
    staffing_jobs = all.joins("LEFT OUTER JOIN admin_staffing_debts ON admin_staffing_debts.admin_staffing_job_id = admin_staffing_jobs.id").where("admin_staffing_debts.admin_staffing_job_id IS null")
    ids = staffing_jobs.map { |job| job.counts_towards_debt? ? job.id : nil }

    all.where(id: ids)
  end

  def ical_calendar(method:)
    cal = Icalendar::Calendar.new
    cal.prodid = "-//Bedlam Theatre//BlackLightning//EN"
    cal.ip_method = method.to_s.upcase

    cal.add_event(to_ical_event)
    cal
  end

  def to_ical_event
    event = Icalendar::Event.new
    event.uid           = "staffing-job-#{id}@bedlamtheatre.co.uk"
    event.dtstart       = Icalendar::Values::DateTime.new(staffable.start_time.utc, "tzid" => "UTC")
    event.dtend         = Icalendar::Values::DateTime.new(staffable.end_time.utc, "tzid" => "UTC")
    event.summary       = "#{staffable.show_title}: #{name}"
    event.description   = "You are staffing #{staffable.show_title} as #{name}."
    event.location      = "Bedlam Theatre, 11b Bristo Place, Edinburgh EH1 1EZ"
    event.last_modified = Icalendar::Values::DateTime.new([ updated_at, staffable.updated_at ].max.utc, "tzid" => "UTC")
    event.sequence      = calendar_sequence
    event
  end

  def bump_calendar_sequence
    update_column(:calendar_sequence, calendar_sequence + 1) unless destroyed?
  end

  # Associates itself with the soonest upcoming Maintenance Debt
  def associate_with_debt(skip_check = false)
    relevant_keys = previous_changes.keys.excluding("created_at", "updated_at")

    # If the only change is the ID of the staffing debt, skip reallocating the debts to prevent a loop.
    # This means that if you update just the staffing debt, you can slightly mess up the debts,
    # but I can't currently think of a better solution.
    return if relevant_keys == [ "admin_staffing_job_id" ]

    # Necessary in some cases, such as when changing the user on the staffing_job and the debt is still nil in the local instance.
    reload

    # If the staffing job is associated with a template, the job does not count towards debt or has no user,
    # do not associate with a debt. Just make sure the debt is nil.
    if self.staffable.is_a?(Admin::StaffingTemplate) || !self.counts_towards_debt? || user.nil?
      staffing_debt.update(admin_staffing_job: nil) if staffing_debt.present?
    else
      # &. makes sure that a staffing_debt is present, and only one of the keys in the array has to have changed for the staffing_debt to be disassociated.
      staffing_debt&.update(admin_staffing_job: nil) if relevant_keys.any? { |key| %w[state user_id staffable_id name].include?(key) }

      user.reallocate_staffing_debts
    end
  end

  def dissassociate_from_debt
    # If the staffing_job is currently associated with a debt, break the association, and reallocate the staffing debts.
    if staffing_debt.present?
      staffing_debt.update(admin_staffing_job: nil)

      user.reallocate_staffing_debts if user.present?
    end
  end

  private

  def send_calendar_invite_email
    # Skip template jobs: they have no real date or time.
    return if staffable.is_a?(Admin::StaffingTemplate)

    if saved_change_to_user_id?
      old_user_id, new_user_id = saved_change_to_user_id

      send_cancellation_to(User.find(old_user_id)) if old_user_id.present?
      StaffingMailer.calendar_invite(self).deliver_later if new_user_id.present?
    elsif saved_change_to_name? && user.present?
      bump_calendar_sequence
      StaffingMailer.calendar_invite(self).deliver_later
    end
  end

  def send_calendar_cancellation_email
    send_cancellation_to(user) if user.present? && !staffable.is_a?(Admin::StaffingTemplate)
  end

  def send_cancellation_to(recipient)
    bump_calendar_sequence
    StaffingMailer.calendar_cancellation(
      recipient: recipient,
      staffing: staffable,
      job_name: name,
      ics_data: ical_calendar(method: :cancel).to_ical
    ).deliver_later
  end
end
