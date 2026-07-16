module Reimbursements
  ##
  # Shared "log the failure, then report it" pattern: a rescue block that logs
  # a message and forwards the error to Honeybadger recurs identically across
  # this diff's jobs and finance controllers, differing only in the message
  # and the Honeybadger context — included by both layers (Reimbursements::
  # ApplicationJob and FinanceController) rather than living in just one.
  module ErrorReporting
    def log_and_notify(message, error, context: {})
      Rails.logger.error(message)
      Honeybadger.notify(error, context: context)
    end
  end
end
