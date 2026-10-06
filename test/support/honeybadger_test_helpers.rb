# Captures Honeybadger calls so a test can assert a failure was REPORTED, not just swallowed.
module HoneybadgerTestHelpers
  def capture_honeybadger_notices(&) = capture_honeybadger(:notify, &)
  def capture_honeybadger_events(&) = capture_honeybadger(:event, &)

  private

  def capture_honeybadger(method_name)
    original = Honeybadger.method(method_name)
    calls = []
    Honeybadger.define_singleton_method(method_name) { |subject, **opts| calls << [ subject, opts ] }
    yield
    calls
  ensure
    Honeybadger.define_singleton_method(method_name, original)
  end
end
