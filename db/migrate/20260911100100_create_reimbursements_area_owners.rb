class CreateReimbursementsAreaOwners < ActiveRecord::Migration[8.1]
  # Mirrors reimbursements_budget_owners exactly. Owners are People (payees),
  # not user accounts.
  def change
    create_table :reimbursements_area_owners do |t|
      t.references :area, type: :bigint, null: false,
                          foreign_key: { to_table: :reimbursements_areas }, index: true
      t.references :person, type: :bigint, null: false,
                            foreign_key: { to_table: :reimbursements_people }, index: true

      t.timestamps

      t.index %i[area_id person_id], unique: true,
              name: "index_reimbursements_area_owners_on_area_id_and_person_id"
    end
  end
end
