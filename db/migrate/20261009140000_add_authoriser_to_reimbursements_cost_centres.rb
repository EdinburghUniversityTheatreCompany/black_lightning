class AddAuthoriserToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  def change
    add_column :reimbursements_cost_centres, :authoriser_name, :string
    add_column :reimbursements_cost_centres, :authoriser_designation, :string
  end
end
