require 'test_helper'

class Admin::MassMailsHelperTest < ActionView::TestCase
  setup do
    @mass_mail = FactoryBot.create :draft_mass_mail
  end

  test 'should return send date' do
    @mass_mail.send_date = DateTime.now.advance(days: 1)
    @mass_mail.save

    assert_not_equal 'No Send Date', get_send_date(@mass_mail)
  end

  test 'should return subject' do
    assert_equal @mass_mail.subject, get_subject(@mass_mail)
  end

  test 'should return sender' do
    @mass_mail.sender = FactoryBot.create(:member)
    @mass_mail.save

    assert_equal @mass_mail.sender.name, get_sender_name(@mass_mail)
  end

  test 'should return message if the send date is not set' do
    @mass_mail.update_attribute :send_date, nil

    assert_equal 'No Send Date', get_send_date(@mass_mail)
  end

  test 'should return message if the subject is not set' do
    @mass_mail.update_attribute :subject, nil

    assert_equal 'No Subject', get_subject(@mass_mail)
  end

  test 'should return message if the sender is not set' do
    @mass_mail.update_attribute :sender, nil

    assert_equal 'No Sender', get_sender_name(@mass_mail)
  end
end