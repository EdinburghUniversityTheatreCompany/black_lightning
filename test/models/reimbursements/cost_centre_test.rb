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
  end
end
