class CreateMaintenanceAttendances < ActiveRecord::Migration[7.0]
  def change
    create_table :maintenance_attendances do |t|
      t.bigint :maintenance_session, null: false, foreign_key: true
      t.integer :user, null: false, foreign_key: true

      t.timestamps
    end

    add_reference :admin_maintenance_debts, :maintenance_attendance, foreign_key: true
  end
end
