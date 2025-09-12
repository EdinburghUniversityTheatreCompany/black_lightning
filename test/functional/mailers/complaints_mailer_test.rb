require "test_helper"

class ComplaintsMailerTest < ActionMailer::TestCase
  test "Email when complaint is created" do
    complaint = FactoryBot.create(:complaint)

    assert_difference "ActionMailer::Base.deliveries.count", 1 do
      # Send the email, then test that it got queued
      email = ComplaintsMailer.new_complaint(complaint).deliver_now
    end
  end
end
