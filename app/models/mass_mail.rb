class MassMail < ActiveRecord::Base
  belongs_to :sender, class_name: 'User'
  has_and_belongs_to_many :recipients, class_name: 'User'

  def send!
    recipients.each do |recipient|
      begin
        MassMailer.send_mail(self, recipient).deliver_now
      rescue => e
        Rails.logger.fatal e.message
      end
    end
  end
  handle_asynchronously :send!, run_at: proc { |m| m.send_date }
end
