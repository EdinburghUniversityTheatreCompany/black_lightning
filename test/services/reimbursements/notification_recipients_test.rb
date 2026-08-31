require "test_helper"

module Reimbursements
  class NotificationRecipientsTest < ActiveSupport::TestCase
    def centre_with(role)
      CostCentre.new(key: "nrt", name: "NRT", eusa_code: "NRT",
                     receive_mailbox: "a@b.co", send_mailbox: "a@b.co",
                     notification_role: role)
    end

    test "returns the notification role's members' emails" do
      role = Role.create!(name: "NRT Finance Admin")
      role.users << users(:member)

      assert_equal [ users(:member).email ], NotificationRecipients.for(centre_with(role))
    end

    test "returns an empty array for a role with no members" do
      assert_empty NotificationRecipients.for(centre_with(Role.create!(name: "NRT Empty")))
    end

    test "returns an empty array when no role is set" do
      assert_empty NotificationRecipients.for(centre_with(nil))
    end

    test "returns an empty array for a nil cost centre" do
      assert_empty NotificationRecipients.for(nil)
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the role entirely" do
      role = Role.create!(name: "NRT Overridden")
      role.users << users(:member)

      with_operator_email("ops@example.com") do
        assert_equal [ "ops@example.com" ], NotificationRecipients.for(centre_with(role))
      end
    end

    test "the override applies even when the centre has no role" do
      with_operator_email("ops@example.com") do
        assert_equal [ "ops@example.com" ], NotificationRecipients.for(centre_with(nil))
      end
    end

    test "de-duplicates and drops blanks" do
      role = Role.create!(name: "NRT Dupes")
      blank = users(:committee)
      blank.update_columns(email: "")
      role.users << users(:member)
      role.users << blank

      assert_equal [ users(:member).email ], NotificationRecipients.for(centre_with(role))
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
