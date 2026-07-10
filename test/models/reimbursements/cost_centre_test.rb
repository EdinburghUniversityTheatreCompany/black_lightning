require "test_helper"

module Reimbursements
  class CostCentreTest < ActiveSupport::TestCase
    test "fringe is the default cost centre with the EUSA F40 code" do
      assert_equal "fringe", CostCentre.default.key
      assert_equal "F40", CostCentre.default.eusa_code
    end

    test "carries distinct receive and send mailboxes" do
      fringe = CostCentre.default
      assert_equal "reimbursements@bedlamfringe.co.uk", fringe.receive_mailbox
      assert_equal "reimbursements@bedlamfringe.co.uk", fringe.send_mailbox
    end

    test "requires key, name, eusa_code and both mailboxes" do
      cost_centre = CostCentre.new
      assert_not cost_centre.valid?
      assert_includes cost_centre.errors.attribute_names, :key
      assert_includes cost_centre.errors.attribute_names, :name
      assert_includes cost_centre.errors.attribute_names, :eusa_code
      assert_includes cost_centre.errors.attribute_names, :receive_mailbox
      assert_includes cost_centre.errors.attribute_names, :send_mailbox
    end

    test "key is unique" do
      duplicate = CostCentre.new(key: "fringe", name: "Dup", eusa_code: "F40",
        receive_mailbox: "a@b.co", send_mailbox: "a@b.co")
      assert_not duplicate.valid?
      assert_includes duplicate.errors.attribute_names, :key
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
        receive_mailbox: "a@b.co", send_mailbox: "a@b.co", nightly_run_days: [ 1, 3, 5 ])
      assert_equal [ 1, 3, 5 ], CostCentre.find(fresh.id).nightly_run_days
    end

    test "nightly_run_days rejects non-weekday values" do
      cc = CostCentre.new(key: "bad", name: "Bad", eusa_code: "B1",
        receive_mailbox: "a@b.co", send_mailbox: "a@b.co", nightly_run_days: [ 2, 9 ])
      assert_not cc.valid?
      assert_includes cc.errors.attribute_names, :nightly_run_days
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

    test "record_nightly_run! stamps the last-run date" do
      cc = CostCentre.default
      cc.record_nightly_run!(Date.new(2026, 7, 9))
      assert_equal Date.new(2026, 7, 9), cc.reload.last_nightly_run_on
    end
  end
end
