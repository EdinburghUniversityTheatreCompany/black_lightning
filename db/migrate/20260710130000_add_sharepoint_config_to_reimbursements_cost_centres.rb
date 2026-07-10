class AddSharepointConfigToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # Per-cost-centre SharePoint destinations (drive + folder ids) for the BACS
  # xlsx and the renamed receipts, plus the EUSA finance recipient. Build Batch
  # (Phase C) reads these; the Settings folder-picker UI (Phase F) edits them.
  # All nullable — a fresh cost centre is configured before its first batch.
  def change
    add_column :reimbursements_cost_centres, :sharepoint_receipts_drive_id, :string
    add_column :reimbursements_cost_centres, :sharepoint_receipts_folder_id, :string
    add_column :reimbursements_cost_centres, :sharepoint_bacs_drive_id, :string
    add_column :reimbursements_cost_centres, :sharepoint_bacs_folder_id, :string
    add_column :reimbursements_cost_centres, :eusa_recipient, :string
  end
end
