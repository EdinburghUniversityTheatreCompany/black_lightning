class CreateMaintenanceSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :maintenance_sessions do |t|
      t.date :date

      t.timestamps
    end
  end
end
