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
require 'test_helper'

class MassMailTest < ActiveSupport::TestCase
  test 'can send unsent mass mail' do
    recipients = FactoryBot.create_list(:member, 5)
    mass_mail = FactoryBot.create(:draft_mass_mail, recipients: recipients, sender: FactoryBot.create(:member))

    mass_mail.prepare_send!

    assert_enqueued_emails 5
  end

  test 'cannot send mass mail without recipients' do
    mass_mail = FactoryBot.create(:draft_mass_mail, sender: FactoryBot.create(:member))

    assert_raise Exceptions::MassMail::NoRecipients do
      mass_mail.prepare_send!
    end

    mass_mail.update recipients: []

    assert_raise Exceptions::MassMail::NoRecipients do
      mass_mail.prepare_send!
    end
  end

  test 'cannot send mass mail without sender' do
    recipients = FactoryBot.create_list(:member, 10)
    mass_mail = FactoryBot.create(:draft_mass_mail, recipients: recipients)

    assert_raise Exceptions::MassMail::NoSender do
      mass_mail.prepare_send!
    end
  end

  test 'cannot send mass mail that is no longer a draft' do
    recipients = FactoryBot.create_list(:member, 10)
    mass_mail = FactoryBot.create(:sent_mass_mail, recipients: recipients, sender: FactoryBot.create(:member))

    assert_raise Exceptions::MassMail::AlreadySent do
      mass_mail.prepare_send!
    end
  end

  test 'cannot send mass mail with a send date in the past' do
    recipients = FactoryBot.create_list(:member, 10)

    mass_mail = FactoryBot.create(:draft_mass_mail, recipients: recipients, sender: FactoryBot.create(:member))
    mass_mail.update_attribute :send_date, DateTime.current.advance(seconds: -1)

    assert_raise ActiveRecord::RecordInvalid do
      mass_mail.prepare_send!
    end

    # Test if the error would be thrown on creation as well.
    assert_raise ActiveRecord::RecordInvalid do
      FactoryBot.create(:draft_mass_mail, send_date: DateTime.current.advance(seconds: -1))
    end
  end

  test 'cannot destroy mass mail that is sent' do
    mass_mail = FactoryBot.create(:sent_mass_mail)

    assert_not mass_mail.destroy

    assert_no_enqueued_emails

    assert_match "The mass mail \"#{mass_mail.subject}\" has already been send.", mass_mail.errors.full_messages.join('')

    mass_mail.update_attribute(:draft, true)

    assert_difference 'MassMail.count', -1 do
      assert mass_mail.destroy
    end
  end
end
