# Captures Honeybadger.notify calls so a test can assert that a failure was
# REPORTED, not just swallowed. Shared by the reimbursements and climate suites,
# both of which rely on ErrorReporting#log_and_notify.
module HoneybadgerTestHelpers
  def capture_honeybadger_notices
    notices = []
    original = Honeybadger.method(:notify)
    Honeybadger.define_singleton_method(:notify) { |error, **opts| notices << [ error, opts ] }
    yield
    notices
  ensure
    Honeybadger.define_singleton_method(:notify, original)
  end

  # Honeybadger.event, as capture_honeybadger_notices does for Honeybadger.notify.
  # The nightly reports an empty notification role as an event, not an error --
  # it is a configuration gap, not an exception.
  def capture_honeybadger_events
    events = []
    original = Honeybadger.method(:event)
    Honeybadger.define_singleton_method(:event) { |name, **payload| events << [ name, payload ] }
    yield
    events
  ensure
    Honeybadger.define_singleton_method(:event, original)
  end
end
