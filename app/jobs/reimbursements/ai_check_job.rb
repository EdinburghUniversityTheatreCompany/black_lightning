module Reimbursements
  ##
  # Runs the AI expense check for one Pending expense and writes the verdict
  # back to Airtable, off the request thread. The Review page enqueues one of
  # these per unchecked Pending expense on load, so the operator isn't blocked
  # waiting on Gemini. Idempotent: skips an expense that already has a verdict.
  #
  # +store_builder+ / +checker_builder+ are the injection seams for tests.
  class AiCheckJob < ApplicationJob
    queue_as :default

    class_attribute :store_builder, default: -> { Store.new }
    class_attribute :checker_builder, default: -> { AiChecker.new }

    def perform(expense_record_id)
      store = store_builder.call
      expense = store.find_expense!(expense_record_id)
      return if expense.nil? || expense.ai_check_status.present?

      result = checker_builder.call.check(expense, store.active_budgets)
      store.update_expense!(expense_record_id,
                            ai_check_status: result.status,
                            ai_comment: result.comment,
                            ai_checked_at: result.checked_at)
    end
  end
end
