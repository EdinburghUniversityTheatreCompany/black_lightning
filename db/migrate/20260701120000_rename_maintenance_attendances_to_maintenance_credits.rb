class RenameMaintenanceAttendancesToMaintenanceCredits < ActiveRecord::Migration[8.1]
  def change
    # On MySQL 8 both operations are fast in-place metadata changes; the app deploys with a full
    # container swap (no rolling old/new-code overlap), so the rename is safe. strong_migrations
    # still flags them, hence safety_assured.
    # Rails' MySQL adapter auto-renames convention-named indexes (and the FK constraint) to follow
    # the new table/column, so no explicit index rename is needed here.
    safety_assured do
      rename_table :maintenance_attendances, :maintenance_credits
      rename_column :admin_maintenance_debts, :maintenance_attendance_id, :maintenance_credit_id
    end
  end
end
