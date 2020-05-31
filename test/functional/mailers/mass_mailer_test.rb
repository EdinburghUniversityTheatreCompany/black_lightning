require 'test_helper'

class MassMailerTest < ActionMailer::TestCase
  include MdHelper

  test 'send_mail' do
    mass_mail = FactoryBot.create(:draft_mass_mail)
    recipient = users(:admin)

    mail = nil

    assert_difference 'ActionMailer::Base.deliveries.count' do
      mail = MassMailer.send_mail(mass_mail, recipient).deliver_now
    end

    assert_equal [recipient.email], mail.to
    assert_equal "Bedlam Theatre - #{mass_mail.subject}", mail.subject
    assert_equal render_markdown(mass_mail.body), mail.html_part.body.to_s
  end
end