class AddStateToStaffingDebts < ActiveRecord::Migration[7.0]
  def up
    add_column :admin_staffing_debts, :state, :bigint, null: false, default: 0

    Admin::StaffingDebt.all.each do |staffing_debt|
      if staffing_debt.forgiven
        staffing_debt.update_columns(state: :forgiven)
      else
        staffing_debt.update_columns(state: :normal)
      end
    end

    rename_column :admin_staffing_debts, :converted, :converted_from_maintenance_debt
    change_column :admin_staffing_debts, :converted_from_maintenance_debt, :boolean, default: false
    remove_column :admin_staffing_debts, :forgiven, :boolean
  end

  def down
    rename_column :admin_staffing_debts, :converted_from_maintenance_debt, :converted

    add_column :admin_staffing_debts, :forgiven, :boolean

    Admin::StaffingDebt.all.each do |staffing_debt|
      p "#{staffing_debt.state} -> #{staffing_debt.status}"
      case Admin::StaffingDebt.states[staffing_debt.state]
      when 0 # Normal, so not forgiven.
        staffing_debt.update(forgiven: false)
      when 1 # Converted to a maintenance debt. This was not tracked before, but forgiven is the closest alternative.
        staffing_debt.update(forgiven: true)
      when 2 # Forgiven, simply matched.
        staffing_debt.update(forgiven: true)
      when 3 # Expired because it got out of date, closest alternative is forgiven.
        staffing_debt.update(forgiven: true)
      end
    end

    remove_column :admin_staffing_debts, :state
  end
end
