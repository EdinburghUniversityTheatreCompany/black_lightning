##
# Helper for the duplicate user report.
##
module Admin::DuplicatesHelper
  ##
  # Years a user was active, taken from the group's pre-computed cache where the report built one
  # and from the model otherwise.
  ##
  def cached_years_active(user, cache = nil)
    return user.years_active unless cache

    cache[user.id] || []
  end
end
