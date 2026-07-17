module Reimbursements
  # ActiveRecord models in this namespace live in reimbursements_* tables
  # (e.g. Reimbursements::CostCentre -> reimbursements_cost_centres). The
  # Airtable-backed POROs (Expense, Person, Budget, …) aren't ActiveRecord, so
  # this prefix doesn't affect them.
  def self.table_name_prefix
    "reimbursements_"
  end

  # The one place that decides which data backend serves the reimbursements
  # portal + operator tooling. Every store_builder seam calls this; flipping
  # REIMBURSEMENTS_BACKEND between "airtable" and "database" is the MySQL
  # cutover switch (see docs/reimbursements/mysql-migration-and-roadmap.md).
  def self.build_store
    case Settings.backend
    when "airtable" then Store.new
    when "database" then DatabaseStore.new
    else
      raise ArgumentError,
            "Unknown REIMBURSEMENTS_BACKEND #{Settings.backend.inspect} (expected \"airtable\" or \"database\")"
    end
  end
end
