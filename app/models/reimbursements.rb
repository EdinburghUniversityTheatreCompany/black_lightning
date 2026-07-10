module Reimbursements
  # ActiveRecord models in this namespace live in reimbursements_* tables
  # (e.g. Reimbursements::CostCentre -> reimbursements_cost_centres). The
  # Airtable-backed POROs (Expense, Person, Budget, …) aren't ActiveRecord, so
  # this prefix doesn't affect them.
  def self.table_name_prefix
    "reimbursements_"
  end
end
