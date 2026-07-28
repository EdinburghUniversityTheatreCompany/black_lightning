module Reimbursements
  # ActiveRecord models in this namespace live in reimbursements_* tables
  # (e.g. Reimbursements::CostCentre -> reimbursements_cost_centres).
  def self.table_name_prefix
    "reimbursements_"
  end

  # The single data gateway every store_builder seam calls. One store per
  # request or job run: DatabaseStore memoizes its lists per instance.
  #
  # +financial_year+ scopes the budget screens to one year; nil (jobs, the
  # producer surfaces) leaves the store unscoped.
  def self.build_store(financial_year: nil)
    DatabaseStore.new(financial_year: financial_year)
  end
end
