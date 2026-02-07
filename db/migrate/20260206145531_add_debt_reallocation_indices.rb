class AddDebtReallocationIndices < ActiveRecord::Migration[8.1]
  def change
    # Indices for maintenance debt reallocation queries
    add_index :admin_maintenance_debts, [ :user_id, :due_by, :state ],
              name: "index_maintenance_debts_on_user_date_state",
              if_not_exists: true
    add_index :admin_maintenance_debts, [ :user_id, :state, :maintenance_attendance_id ],
              name: "index_maintenance_debts_reallocation",
              if_not_exists: true

    # Indices for staffing debt reallocation queries
    add_index :admin_staffing_debts, [ :user_id, :due_by, :state ],
              name: "index_staffing_debts_on_user_date_state",
              if_not_exists: true
    add_index :admin_staffing_debts, [ :user_id, :state, :admin_staffing_job_id ],
              name: "index_staffing_debts_reallocation",
              if_not_exists: true

    # Note: team_members index already exists in the database, skipping
  end
end
