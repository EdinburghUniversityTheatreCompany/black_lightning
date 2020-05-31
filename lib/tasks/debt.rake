require "#{Rails.root}/lib/tasks/logic/debt_task_logic"

namespace :debt do
  # :nocov: 
  desc 'notifies users who have gone into debt recently or have been in debt for a while'
  # Should be run early morning not late at night.
  task notify_debtors: :environment do
    DebtTaskLogic.notify_debtors

    p 'Notified all debtors'
  end

  desc 'clears all debt records, staffing records, and notification records'
  task clear_all_debts: :environment do
    DebtTaskLogic.clear_all_debts

    p 'All debt records cleared'
  end
  # :nocov:
end
