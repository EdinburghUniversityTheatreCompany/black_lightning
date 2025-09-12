# == Schema Information
#
# Table name: mass_mails
#
# *id*::         <tt>integer, not null, primary key</tt>
# *sender_id*::  <tt>integer</tt>
# *subject*::    <tt>string(255)</tt>
# *body*::       <tt>text(65535)</tt>
# *send_date*::  <tt>datetime</tt>
# *draft*::      <tt>boolean</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class MassMail < ApplicationRecord
  validate :send_date_is_not_in_the_past
  validates :subject, :body, presence: true

  belongs_to :sender, class_name: "User", optional: true
  has_and_belongs_to_many :recipients, class_name: "User", optional: true

  before_destroy :check_if_mail_has_been_sent

  normalizes :subject, with: ->(subject) { subject&.strip }

  def self.ransackable_attributes(auth_object = nil)
    %w[body draft send_date sender_id subject]
  end

  def send_date_is_not_in_the_past
    errors.add(:send_date, "cannot be in the past") if send_date_is_in_the_past?
  end

  def prepare_send!
    raise(Exceptions::MassMail::NoRecipients, "There are no recipients") if recipients.nil? || recipients.empty?
    raise(Exceptions::MassMail::NoSender, "There is no sender") if sender.nil?
    raise(Exceptions::MassMail::AlreadySent, "The mass mail has already been send") unless draft

    raise ActiveRecord::RecordInvalid.new(self) if invalid?

    send!

    # Cannot save because the object cannot be saved when draft is false to prevent editing it.
    update(draft: false)
  end

  private

  def send_date_is_in_the_past?
    !send_date.present? || (send_date.present? && send_date < DateTime.current)
  end

  def check_if_mail_has_been_sent
    return if draft

    errors.add(:destroy, "The mass mail \"#{subject}\" has already been send.")
    throw(:abort)
  end

  def send!
    # Schedule the mass mail job for the specified send_date
    MassMailJob.set(wait_until: send_date).perform_later(id)
  end

  # Removed delayed_job handle_asynchronously - now using MassMailJob with ActiveJob
end
