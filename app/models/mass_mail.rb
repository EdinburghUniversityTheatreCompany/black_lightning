class MassMail < ApplicationRecord
  validate :send_date_is_not_in_the_past
  validates :subject, :body, presence: true

  belongs_to :sender, class_name: 'User', optional: true
  has_and_belongs_to_many :recipients, class_name: 'User', optional: true

  before_destroy :check_if_mail_has_been_sent

  def send_date_is_not_in_the_past
    errors.add(:send_date, 'cannot be in the past') if send_date_is_in_the_past?
  end

  def prepare_send!
    raise(Exceptions::MassMail::NoRecipients, 'There are no recipients') if recipients.nil? || recipients.empty?
    raise(Exceptions::MassMail::NoSender, 'There is no sender') if sender.nil?
    raise(Exceptions::MassMail::AlreadySent, 'The mass mail has already been send') unless draft

    raise ActiveRecord::RecordInvalid.new(self) if invalid?

    send!

    # Cannot save because the object cannot be saved when draft is false to prevent editing it.
    update(draft: false)
  end

  private

  def send_date_is_in_the_past?
    return !send_date.present? || (send_date.present? && send_date < DateTime.now)
  end

  def check_if_mail_has_been_sent
    return if draft

    errors.add(:destroy, "The mass mail \"#{subject}\" has already been send.")
    throw(:abort)
  end

  def send!
    recipients.each do |recipient|
      begin
        MassMailer.send_mail(self, recipient).deliver_later
      rescue => e
        # :nocov:
        Rails.logger.fatal e.message
        # :nocov:
      end
    end
  end

  handle_asynchronously :send!, run_at: proc { |m| m.send_date }
end
