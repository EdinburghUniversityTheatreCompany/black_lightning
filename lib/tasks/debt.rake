require "#{Rails.root}/lib/tasks/logic/debt"

namespace :debt do
  # simplecov:disable
  desc "notifies users who have gone into debt recently or have been in debt for a while"
  # Should be run early morning not late at night.
  task notify_debtors: :environment do
    Tasks::Logic::Debt.notify_debtors

    p "Notified all debtors"
  end

  desc "expires all outdated debt"
  task expire_outdated_debt: :environment do
    Tasks::Logic::Debt.expire_outdated_debt

    p "Expired outdated debt."
  end
  # simplecov:enable
end
