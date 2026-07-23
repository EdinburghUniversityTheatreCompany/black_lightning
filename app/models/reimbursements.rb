module Reimbursements
  # ActiveRecord models in this namespace live in reimbursements_* tables
  # (e.g. Reimbursements::CostCentre -> reimbursements_cost_centres).
  def self.table_name_prefix
    "reimbursements_"
  end

  # The single data gateway every store_builder seam calls. The MySQL cutover
  # is complete, so the ActiveRecord-backed DatabaseStore is now the only
  # backend (the Airtable layer was removed in the post-flip cleanup).
  def self.build_store
    DatabaseStore.new
  end
end
