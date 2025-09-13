# This script is run daily by the crontab in the cron container as defined by config/deploy.yml

# Notify the marketing manager if there are any marketing creatives sign ups
bundle exec rails marketing_creatives:notify_of_new_sign_ups

# Clean up personal info in accordance with the privacy policy.
bundle exec rails users:clean_up_personal_info

# Purge unattached blobs
bundle exec rails active_storage:purge_unattached

# Expire old debts
bundle exec rake debt:expire_outdated_debt

# Notify debtors
bundle exec rake debt:notify_debtors 

# Let Honeybadger know we did it.
curl https://api.honeybadger.io/v1/check_in/wqI0PL
