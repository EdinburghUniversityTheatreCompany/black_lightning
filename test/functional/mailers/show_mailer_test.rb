require 'test_helper'

class ShowMailerTest < ActionMailer::TestCase
  test 'send debtors' do
    show = FactoryBot.create(:show)
    user = users(:admin)
    new_debtors_string = 'Finbar the Viking and Dennis the Donkey'

    mail = nil

    assert_difference 'ActionMailer::Base.deliveries.count' do
      mail = ShowMailer.warn_committee_about_debtors_added_to_show(show, new_debtors_string, user).deliver_now
    end

    assert_equal ['productions@bedlamtheatre.co.uk'], mail.to
    assert_equal "New debtors added to #{show.name}", mail.subject

    assert_includes mail.html_part.to_s, new_debtors_string
    assert_includes mail.html_part.to_s, user.name

    assert_includes mail.text_part.to_s, new_debtors_string
    assert_includes mail.text_part.to_s, user.name
  end
end
