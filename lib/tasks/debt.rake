require "#{Rails.root}/lib/tasks/logic/debt"

namespace :debt do
  # :nocov: 
  desc 'notifies users who have gone into debt recently or have been in debt for a while'
  # Should be run early morning not late at night.
  task notify_debtors: :environment do
    Tasks::Logic::Debt.notify_debtors

    p 'Notified all debtors'
  end

  desc 'clears all debt records, staffing records, and notification records'
  task clear_all_debts: :environment do
    Tasks::Logic::Debt.clear_all_debts

    p 'All debt and staffing records cleared.'
  end
  # :nocov:
end
