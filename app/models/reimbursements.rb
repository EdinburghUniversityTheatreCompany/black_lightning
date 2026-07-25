module Reimbursements
  # ActiveRecord models in this namespace live in reimbursements_* tables
  # (e.g. Reimbursements::CostCentre -> reimbursements_cost_centres).
  def self.table_name_prefix
    "reimbursements_"
  end

  # The single data gateway every store_builder seam calls. One store per
  # request or job run: DatabaseStore memoizes its lists per instance.
  def self.build_store
    DatabaseStore.new
  end
end
