class CreateReimbursementsAreas < ActiveRecord::Migration[8.1]
  # A show, project or heading that several budget lines belong to. Both cost
  # centres already invented this: Fringe writes it into budget NAMES
  # ("Cogito: Marketing"), termtime writes it as amountless header rows in its
  # spreadsheet. Neither survived the import.
  #
  # reimbursements_budgets is a live, populated table, so adding its area_id
  # foreign key needs strong_migrations' MySQL-safe path (SET SESSION
  # foreign_key_checks = 0 around the ADD CONSTRAINT, so it validates nothing
  # and never full-table-locks) rather than a plain add_reference(foreign_key:
  # true) — the FK on the brand-new reimbursements_areas table's own columns
  # is exempt (strong_migrations never flags add_foreign_key inside
  # create_table, since the table is guaranteed empty).
  def up
    create_table :reimbursements_areas do |t|
      t.string  :name, null: false
      t.decimal :initial_budget, precision: 12, scale: 2
      t.text    :notes
      t.boolean :active, null: false, default: true
      t.references :cost_centre, type: :bigint, null: true,
                                 foreign_key: { to_table: :reimbursements_cost_centres }, index: true
      t.references :financial_year, type: :bigint, null: true,
                                    foreign_key: { to_table: :reimbursements_financial_years }, index: true

      t.timestamps

      # Matched by name within one (year, centre) — the same rule BudgetImport
      # uses for a budget line, so an area recurs each year as a budget does.
      t.index %i[financial_year_id cost_centre_id name],
              name: "index_reimbursements_areas_on_year_centre_name"
    end

    add_reference :reimbursements_budgets, :area, type: :bigint, null: true, index: true

    safety_assured do
      begin
        execute "SET SESSION foreign_key_checks = 0"
        add_foreign_key :reimbursements_budgets, :reimbursements_areas, column: :area_id
      ensure
        execute "SET SESSION foreign_key_checks = 1"
      end
    end
  end

  def down
    remove_foreign_key :reimbursements_budgets, :reimbursements_areas, column: :area_id
    remove_reference :reimbursements_budgets, :area
    drop_table :reimbursements_areas
  end
end
