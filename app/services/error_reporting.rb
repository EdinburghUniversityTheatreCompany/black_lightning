##
# Shared "log the failure, then report it" pattern: a rescue block that logs a
# message and forwards the error to Honeybadger recurs identically across the
# background jobs and the admin controllers that talk to external services,
# differing only in the message and the Honeybadger context. Included by each
# layer rather than living in just one.
module ErrorReporting
  def log_and_notify(message, error, context: {})
    Rails.logger.error(message)
    Honeybadger.notify(error, context: context)
  end
end
