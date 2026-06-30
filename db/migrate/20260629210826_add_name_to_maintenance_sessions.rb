class AddNameToMaintenanceSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :maintenance_sessions, :name, :string
  end
end
