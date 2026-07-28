class MakeReimbursementsFinancialYearKeyNotNull < ActiveRecord::Migration[8.1]
  # Step 2 of the multi-step add: the previous migration added +key+ nullable
  # and backfilled it, so the constraint can go on now. A year without a key is
  # unreachable in the UI (it is the URL), so NOT NULL states the real rule
  # rather than leaving the model's presence validation as the only guard.
  def up
    change_column_null :reimbursements_financial_years, :key, false
  end

  def down
    change_column_null :reimbursements_financial_years, :key, true
  end
end
