module Reimbursements
  ##
  # A row from the Airtable EUSA Actuals table — EUSA's ledger export, imported
  # during reconciliation. bedlam-bacs kept these as raw dicts; this PORO gives
  # the reconcile flow a typed shape for dedup (nominal_code + narrative + debit
  # + credit, via Reconciliation.actuals_row_dedup_key) and for showing links.
  class EusaActual
    attr_reader :record_id, :nominal_code, :cost_centre, :ref, :date, :period,
                :narrative, :narrative_1, :debit, :credit, :net,
                :linked_expense_ids, :linked_budget_ids, :source_month, :imported_at

    def initialize(record_id:, nominal_code: "", cost_centre: "", ref: "", date: nil,
                   period: "", narrative: "", narrative_1: "", debit: nil, credit: nil,
                   net: nil, linked_expense_ids: [], linked_budget_ids: [],
                   source_month: "", imported_at: nil)
      @record_id = record_id
      @nominal_code = nominal_code
      @cost_centre = cost_centre
      @ref = ref
      @date = date
      @period = period
      @narrative = narrative
      @narrative_1 = narrative_1
      @debit = debit
      @credit = credit
      @net = net
      @linked_expense_ids = linked_expense_ids
      @linked_budget_ids = linked_budget_ids
      @source_month = source_month
      @imported_at = imported_at
    end

    # Key matching Reconciliation.actuals_row_dedup_key so an imported row can be
    # compared against a freshly-parsed ActualsRow to skip re-importing.
    def dedup_key
      Reconciliation.actuals_row_dedup_key(nominal_code, narrative, debit, credit)
    end
  end
end
