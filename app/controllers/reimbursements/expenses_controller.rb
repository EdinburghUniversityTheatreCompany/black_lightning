module Reimbursements
  ##
  # A producer's own expenses: list with live status from Airtable.
  class ExpensesController < BaseController
    def index
      if params[:refresh].present?
        store.refresh_expenses!
        redirect_to reimbursements_expenses_path and return
      end

      @title = "My Reimbursements"
      @expenses = current_person ? store.expenses_for(current_person.record_id) : []
    end
  end
end
