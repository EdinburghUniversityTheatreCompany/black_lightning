class AddShortCodeToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # Nullable with no default and no backfill: the column only labels a picker,
  # and CostCentre#picker_prefix falls back to eusa_code until someone fills it
  # in, so an unset centre reads "F40 - ..." rather than " - ...".
  def change
    add_column :reimbursements_cost_centres, :short_code, :string, limit: 16
  end
end
