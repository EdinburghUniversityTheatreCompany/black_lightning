require "#{Rails.root}/lib/tasks/logic/marketing_creatives"

namespace :marketing_creatives do
  # :nocov:
  desc 'Emails the Marketing Manager with all sign-ups for Marketing Creatives Profiles in the past 25 hours. Should be a rake task.'
  task notify_of_new_sign_ups: :environment do
    Tasks::Logic::MarketingCreatives.notify_of_new_sign_ups
  end
  # :nocov:
end
