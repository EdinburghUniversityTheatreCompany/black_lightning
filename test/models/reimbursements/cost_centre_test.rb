require "test_helper"

module Reimbursements
  class CostCentreTest < ActiveSupport::TestCase
    test "caps the BACS budget holder fields at their column length" do
      fringe = CostCentre.default
      fringe.assign_attributes(authoriser_name: "a" * 256, authoriser_designation: "b" * 256)

      assert_not fringe.valid?
      assert fringe.errors[:authoriser_name].present?
      assert fringe.errors[:authoriser_designation].present?
    end

    def contact_centre(receive: "in@example.com", send: "out@example.com", notify: nil)
      CostCentre.new(receive_mailbox: receive, send_mailbox: send, notification_email: notify)
    end

    # The receive mailbox is polled by email-in, so a question sent there is auto-answered and
    # filed as a receipt rather than read by a person.
    test "contact_email is the first notification address, else a send mailbox that is not polled" do
      assert_equal "finance@example.com",
                   contact_centre(notify: " finance@example.com ; ops@example.com").contact_email
      assert_equal "out@example.com", contact_centre.contact_email
      assert_nil contact_centre(send: "in@example.com").contact_email
    end

    test "sharepoint_graph_site_path converts the site URL to Graph's path form, nil without a valid one" do
      cost_centre = CostCentre.default
      cost_centre.sharepoint_site_url = "https://tenant.sharepoint.com/sites/Finance/"
      assert_equal "tenant.sharepoint.com:/sites/Finance", cost_centre.sharepoint_graph_site_path

      cost_centre.sharepoint_site_url = nil
      assert_nil cost_centre.sharepoint_graph_site_path
      cost_centre.sharepoint_site_url = "not a url"
      assert_nil cost_centre.sharepoint_graph_site_path
    end

    test "key auto-derives from the name (parameterized) when left blank" do
      cc = CostCentre.new(name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "tt-in@b.co", send_mailbox: "tt-out@b.co")
      cc.valid?
      assert_equal "bedlam-termtime", cc.key
    end

    test "an explicit key is kept, not overwritten by the name" do
      cc = CostCentre.new(name: "Bedlam Termtime", key: "tt", eusa_code: "BED",
        receive_mailbox: "tt-in@b.co", send_mailbox: "tt-out@b.co")
      cc.valid?
      assert_equal "tt", cc.key
    end

    test "rejects a key with spaces or uppercase — it must be a URL slug" do
      cc = CostCentre.new(name: "X", key: "Bad Key", eusa_code: "BK1",
        receive_mailbox: "bk-in@b.co", send_mailbox: "bk-out@b.co")
      assert_not cc.valid?
      assert_includes cc.errors.attribute_names, :key

      cc.key = "UPPER"
      assert_not cc.valid?
      assert_includes cc.errors.attribute_names, :key
    end

    test "accepts a lowercase-hyphen-digit slug as the key" do
      cc = CostCentre.new(name: "X", key: "venue-2027", eusa_code: "BK2",
        receive_mailbox: "bk2-in@b.co", send_mailbox: "bk2-out@b.co",
        notification_email: "bk2@b.co")
      assert cc.valid?, cc.errors.full_messages.to_sentence
    end

    test "a mailbox is unique, case-insensitively" do
      %i[receive_mailbox send_mailbox].each do |mailbox|
        duplicate = CostCentre.new(key: "termtime", name: "Termtime", eusa_code: "BED",
          receive_mailbox: "termtime-in@b.co", send_mailbox: "termtime-out@b.co")
        duplicate[mailbox] = "REIMBURSEMENTS@bedlamfringe.co.uk"

        assert_not duplicate.valid?
        assert_includes duplicate.errors.attribute_names, mailbox
      end
    end

    test "rejects a mistyped receive or send mailbox" do
      cost_centre = CostCentre.new(key: "termtime", name: "Termtime", eusa_code: "BED",
        receive_mailbox: "not-an-email", send_mailbox: "termtime-out@b.co")
      assert_not cost_centre.valid?
      assert_includes cost_centre.errors.attribute_names, :receive_mailbox

      cost_centre.receive_mailbox = "termtime-in@b.co"
      cost_centre.send_mailbox = "also not an email"
      assert_not cost_centre.valid?
      assert_includes cost_centre.errors.attribute_names, :send_mailbox
    end

    test "rejects a mistyped eusa_recipient, but blank is still allowed" do
      cost_centre = CostCentre.new(key: "termtime", name: "Termtime", eusa_code: "BED",
        receive_mailbox: "termtime-in@b.co", send_mailbox: "termtime-out@b.co",
        eusa_recipient: "not-an-email", notification_email: "termtime@b.co")
      assert_not cost_centre.valid?
      assert_includes cost_centre.errors.attribute_names, :eusa_recipient

      cost_centre.eusa_recipient = ""
      assert cost_centre.valid?, cost_centre.errors.full_messages.to_sentence
    end

    test "sharepoint_configured? is false until both drive/folder pairs are set" do
      cost_centre = CostCentre.new(sharepoint_receipts_drive_id: "d", sharepoint_receipts_folder_id: "f")
      assert_not cost_centre.sharepoint_configured?, "needs the BACS folder too"

      cost_centre.sharepoint_bacs_drive_id = "d2"
      cost_centre.sharepoint_bacs_folder_id = "f2"
      assert cost_centre.sharepoint_configured?
      assert_equal "d", cost_centre.receipts_folder.drive_id
      assert_equal "f2", cost_centre.bacs_folder.folder_id
    end

    test "sharepoint_fully_configured? also requires the site URL (the badge, not the upload gate)" do
      cost_centre = CostCentre.new(sharepoint_receipts_drive_id: "d", sharepoint_receipts_folder_id: "f",
                                   sharepoint_bacs_drive_id: "d2", sharepoint_bacs_folder_id: "f2")
      # Folders alone let BatchProcessor upload, but the badge needs the site URL.
      assert cost_centre.sharepoint_configured?
      assert_not cost_centre.sharepoint_fully_configured?

      cost_centre.sharepoint_site_url = "https://tenant.sharepoint.com/sites/Finance"
      assert cost_centre.sharepoint_fully_configured?
    end

    test "eusa_recipient_or_default falls back to EUSA finance" do
      assert_equal "finance@eusa.ed.ac.uk", CostCentre.new.eusa_recipient_or_default
      assert_equal "custom@eusa.ed.ac.uk",
                   CostCentre.new(eusa_recipient: "custom@eusa.ed.ac.uk").eusa_recipient_or_default
    end

    # --- Nightly scheduling -----------------------------------------------

    test "nightly_run_days defaults to Tue/Thu and round-trips as an integer array" do
      fresh = CostCentre.new
      assert_equal [ 2, 4 ], fresh.nightly_run_days

      fresh = CostCentre.create!(key: "roundtrip", name: "RT", eusa_code: "RT1",
        receive_mailbox: "a@b.co", send_mailbox: "a@b.co", nightly_run_days: [ 1, 3, 5 ],
        notification_email: "rt@b.co")
      assert_equal [ 1, 3, 5 ], CostCentre.find(fresh.id).nightly_run_days
    end

    test "nightly_run_days rejects non-weekday values and an empty list" do
      # An empty list would silently disable the nightly.
      [ [ 2, 9 ], [] ].each do |days|
        cc = CostCentre.new(key: "bad", name: "Bad", eusa_code: "B1",
          receive_mailbox: "a@b.co", send_mailbox: "a@b.co", nightly_run_days: days)
        assert_not cc.valid?, days.inspect
        assert_includes cc.errors.attribute_names, :nightly_run_days
      end
    end

    test "nightly_run_today? checks the configured run-days by Ruby wday" do
      cc = CostCentre.new(nightly_run_days: [ 2, 4 ]) # Tue, Thu
      assert cc.nightly_run_today?(Date.new(2026, 7, 7)),  "2026-07-07 is a Tuesday"
      assert cc.nightly_run_today?(Date.new(2026, 7, 9)),  "2026-07-09 is a Thursday"
      assert_not cc.nightly_run_today?(Date.new(2026, 7, 8)), "Wednesday is not a run-day"
    end

    test "nightly_due? fires on a fresh run-day and dedups once recorded" do
      cc = CostCentre.new(nightly_run_days: [ 2, 4 ], last_nightly_run_on: nil)
      thursday = Date.new(2026, 7, 9)
      assert cc.nightly_due?(thursday), "never run -> due on a run-day"

      cc.last_nightly_run_on = thursday
      assert_not cc.nightly_due?(thursday), "already ran today -> not due"
      assert_not cc.nightly_due?(Date.new(2026, 7, 10)), "Friday after a Thursday run -> not due"
    end

    test "nightly_due? catches up when the previous run-day was missed" do
      # Ran Tuesday, machine was down Thursday, job runs Friday: Thursday still due.
      cc = CostCentre.new(nightly_run_days: [ 2, 4 ], last_nightly_run_on: Date.new(2026, 7, 7))
      assert cc.nightly_due?(Date.new(2026, 7, 10)), "Friday catches up the missed Thursday"
    end

    test "nightly_due? is false when no run-days are configured" do
      cc = CostCentre.new(nightly_run_days: [], last_nightly_run_on: nil)
      assert_not cc.nightly_due?(Date.new(2026, 7, 9))
    end

    test "next_nightly_run_day returns the next configured day after a date" do
      cc = CostCentre.new(nightly_run_days: [ 2, 4 ]) # Tue, Thu
      assert_equal Date.new(2026, 7, 9), cc.next_nightly_run_day(Date.new(2026, 7, 7)) # Tue -> Thu
      assert_equal Date.new(2026, 7, 14), cc.next_nightly_run_day(Date.new(2026, 7, 9)) # Thu -> next Tue
      assert_nil CostCentre.new(nightly_run_days: []).next_nightly_run_day(Date.new(2026, 7, 9))
    end

    # --- Notification email ------------------------------------------------

    test "notification_emails splits on semicolons and commas, stripping and de-duplicating" do
      centre = CostCentre.new(notification_email: " finance@b.co ;business@b.co,\nfinance@b.co ;; ")

      assert_equal [ "finance@b.co", "business@b.co" ], centre.notification_emails
    end

    test "notification_emails is empty when the column is blank" do
      assert_empty CostCentre.new(notification_email: nil).notification_emails
      assert_empty CostCentre.new(notification_email: "  ").notification_emails
      assert_predicate CostCentre.new(notification_email: nil), :notification_recipients_empty?
      assert_not_predicate CostCentre.new(notification_email: "finance@b.co"), :notification_recipients_empty?
    end

    test "a cost centre with no notification email is invalid" do
      centre = CostCentre.new(key: "ne2", name: "NE Two", eusa_code: "NE2",
                              receive_mailbox: "a@b.co", send_mailbox: "a@b.co")

      assert_not centre.valid?
      assert_includes centre.errors.attribute_names, :notification_email
    end

    test "one mistyped address in the list invalidates the whole field" do
      centre = CostCentre.new(key: "ne3", name: "NE Three", eusa_code: "NE3",
                              receive_mailbox: "a@b.co", send_mailbox: "a@b.co",
                              notification_email: "finance@b.co; not-an-email")

      assert_not centre.valid?
      assert_includes centre.errors.attribute_names, :notification_email
    end

    test "operator_recipients is the centre's notification addresses" do
      assert_equal [ "finance@b.co" ], CostCentre.new(notification_email: "finance@b.co").operator_recipients
    end

    test "REIMBURSEMENTS_OPERATOR_EMAIL overrides the centre's addresses entirely" do
      with_operator_email("ops@example.com") do
        assert_equal [ "ops@example.com" ], CostCentre.new(notification_email: "finance@b.co").operator_recipients
      end
    end

    test "the operator override applies even when the centre has no address" do
      with_operator_email("ops@example.com") do
        assert_equal [ "ops@example.com" ], CostCentre.new(notification_email: nil).operator_recipients
      end
    end

    test "picker_prefix is the short code, falling back to the eusa code" do
      assert_equal "BF", CostCentre.new(eusa_code: "F40", short_code: "BF").picker_prefix
      # The column is never backfilled, so most centres have none.
      assert_equal "F40", CostCentre.new(eusa_code: "F40", short_code: "").picker_prefix
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
