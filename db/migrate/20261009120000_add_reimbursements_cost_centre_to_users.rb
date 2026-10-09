class AddReimbursementsCostCentreToUsers < ActiveRecord::Migration[8.1]
  # A finance user's home cost centre, which only decorates their links.
  # users is populated, so the FK goes on with strong_migrations' MySQL-safe
  # path (foreign_key_checks off around ADD CONSTRAINT) rather than
  # add_reference(foreign_key: true). Nullify on delete: a default must never
  # stop a centre being removed.
  def up
    add_reference :users, :reimbursements_cost_centre, type: :bigint, null: true, index: true

    safety_assured do
      begin
        execute "SET SESSION foreign_key_checks = 0"
        add_foreign_key :users, :reimbursements_cost_centres, column: :reimbursements_cost_centre_id,
                                                              on_delete: :nullify
      ensure
        execute "SET SESSION foreign_key_checks = 1"
      end
    end
  end

  def down
    remove_foreign_key :users, column: :reimbursements_cost_centre_id
    remove_reference :users, :reimbursements_cost_centre
  end
end
