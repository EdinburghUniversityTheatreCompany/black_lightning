# Captures Honeybadger calls so a test can assert a failure was REPORTED, not just swallowed.
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
