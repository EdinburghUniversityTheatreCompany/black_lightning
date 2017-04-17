class CreateAdminMaintenanceDebts < ActiveRecord::Migration
  def change
    create_table :admin_maintenance_debts do |t|
      t.integer :user_id
      t.date :due_by
      t.integer :show_id

      t.timestamps null: false
    end
  end
end
