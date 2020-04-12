class MassMail < ApplicationRecord
  validate :send_date_is_not_in_the_past
  validates :subject, :body, presence: true

  belongs_to :sender, class_name: 'User'
  has_and_belongs_to_many :recipients, class_name: 'User'

  def send_date_is_not_in_the_past
    errors.add(:send_date, 'cannot be in the past') if send_date_is_in_the_past?
  end

  def prepare_send!
    raise(Exceptions::MassMail::NoRecipients.new('There are no recipients')) if recipients.nil? || recipients.empty?
    raise(Exceptions::MassMail::NoSender.new('There is no sender')) if sender.nil?
    raise(Exceptions::MassMail::AlreadySent.new('The mass mail has already been send')) unless draft

    raise ActiveRecord::InvalidRecord.new(self) if invalid?

    update draft: false

    send!
  end

  private

  def send_date_is_in_the_past?
    return !send_date.present? || (send_date.present? && send_date < DateTime.now)
  end

  def send!
    recipients.each do |recipient|
      begin
        MassMailer.send_mail(self, recipient).deliver_now
      rescue => e
        # :nocov:
        Rails.logger.fatal e.message
        # :nocov:
      end
    end
  end

  handle_asynchronously :send!, run_at: proc { |m| m.send_date }
end
