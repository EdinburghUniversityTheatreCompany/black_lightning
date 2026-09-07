require "test_helper"

module Reimbursements
  class NotificationRecipientsTest < ActiveSupport::TestCase
    def centre_with(notification_email)
      CostCentre.new(key: "nrt", name: "NRT", eusa_code: "NRT",
                     receive_mailbox: "a@b.co", send_mailbox: "a@b.co",
                     notification_email: notification_email)
    end

    test "returns the cost centre's notification addresses" do
      assert_equal [ "finance@bedlamfringe.co.uk" ],
                   NotificationRecipients.for(centre_with("finance@bedlamfringe.co.uk"))
    end

    test "splits a multi-address notification email on semicolons and commas" do
      centre = centre_with("finance@b.co; business@b.co,  finance@b.co ")

      assert_equal [ "finance@b.co", "business@b.co" ], NotificationRecipients.for(centre)
    end

    test "returns an empty array when no address is set" do
      assert_empty NotificationRecipients.for(centre_with(nil))
      assert_empty NotificationRecipients.for(centre_with("  "))
    end

    test "returns an empty array for a nil cost centre" do
      assert_empty NotificationRecipients.for(nil)
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the address entirely" do
      with_operator_email("ops@example.com") do
        assert_equal [ "ops@example.com" ],
                     NotificationRecipients.for(centre_with("finance@bedlamfringe.co.uk"))
      end
    end

    test "the override applies even when the centre has no address" do
      with_operator_email("ops@example.com") do
        assert_equal [ "ops@example.com" ], NotificationRecipients.for(centre_with(nil))
      end
    end

    private

    def with_operator_email(value)
      previous = ENV["REIMBURSEMENTS_OPERATOR_EMAIL"]
      ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = value
      yield
    ensure
      previous.nil? ? ENV.delete("REIMBURSEMENTS_OPERATOR_EMAIL") : ENV["REIMBURSEMENTS_OPERATOR_EMAIL"] = previous
    end
  end
end
