class AddEusaContactNameToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # Who the BACS request email is addressed TO — the EUSA finance person handling
  # our payments, which changes with EUSA's staffing. Nullable: blank keeps the
  # generic "Finance Team" greeting.
  def change
    add_column :reimbursements_cost_centres, :eusa_contact_name, :string
  end
end
