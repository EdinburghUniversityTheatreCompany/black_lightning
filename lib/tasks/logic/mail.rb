# Please use deliver_now in rake tasks.
class Tasks::Logic::Mail
  def self.send_test_email(email_address)
    p "Sending Test Email to #{email_address}..."
    TestMailer.test_email(email_address).deliver_now
    p 'Sent Test email'
  end
end