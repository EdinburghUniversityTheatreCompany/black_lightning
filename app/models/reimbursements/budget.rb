module Reimbursements
  ##
  # A budget category in the Airtable Budgets table.
  class Budget
    attr_reader :record_id, :name, :nominal_code, :active

    def initialize(record_id:, name:, nominal_code: "", active: true)
      @record_id = record_id
      @name = name
      @nominal_code = nominal_code
      @active = active
    end
  end
end
