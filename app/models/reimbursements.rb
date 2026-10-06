module Reimbursements
  # Models here live in reimbursements_* tables.
  def self.table_name_prefix
    "reimbursements_"
  end

  # The data gateway every store_builder seam calls; one store per request or job run,
  # as DatabaseStore memoizes its lists per instance. A nil +financial_year+ or
  # +cost_centre+ leaves that axis unscoped.
  def self.build_store(financial_year: nil, cost_centre: nil)
    DatabaseStore.new(financial_year: financial_year, cost_centre: cost_centre)
  end
end
