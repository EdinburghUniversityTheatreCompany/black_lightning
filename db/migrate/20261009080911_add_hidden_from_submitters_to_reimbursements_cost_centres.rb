class AddHiddenFromSubmittersToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  def change
    add_column :reimbursements_cost_centres, :hidden_from_submitters, :boolean, default: false, null: false
  end
end
