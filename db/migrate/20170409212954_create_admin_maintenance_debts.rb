class CreateAdminMaintenanceDebts < ActiveRecord::Migration
  def change
    create_table :admin_maintenance_debts do |t|
      t.integer :user_id
      t.date :dueBy
      t.integer :show_id

      t.timestamps null: false
    end
  end
end
