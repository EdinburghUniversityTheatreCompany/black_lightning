require "test_helper"

class Display::RotationTest < ActiveSupport::TestCase
  setup do
    # The cursor is cache state and the process keeps its cache between tests:
    # without this, where the last test left it decides what this one sees.
    Rails.cache.clear
  end

  test "walks the whole list in order and then wraps" do
    positions = 4.times.map { Display::Rotation.next_index("panel", size: 3) }

    assert_equal [ 0, 1, 2, 0 ], positions
  end

  test "starts at the first entry" do
    assert_equal 0, Display::Rotation.next_index("panel", size: 5)
  end

  test "a single entry never moves" do
    3.times { assert_equal 0, Display::Rotation.next_index("panel", size: 1) }
  end

  test "an empty list is index zero rather than an error" do
    assert_equal 0, Display::Rotation.next_index("panel", size: 0)
  end

  test "each panel keeps its own cursor" do
    Display::Rotation.next_index("one", size: 3)
    Display::Rotation.next_index("one", size: 3)

    assert_equal 0, Display::Rotation.next_index("two", size: 3)
  end

  test "each day starts over" do
    Display::Rotation.next_index("panel", size: 3, on: Date.new(2026, 8, 26))

    assert_equal 0, Display::Rotation.next_index("panel", size: 3, on: Date.new(2026, 8, 27))
  end

  test "a cache that cannot answer still moves the slide on" do
    # Solid Cache's failsafe returns nil when its database is unreachable.
    seen = with_null_cache { 20.times.map { Display::Rotation.next_index("panel", size: 4) } }

    assert seen.all? { |index| (0...4).cover?(index) }, "fallback returned an out-of-range index: #{seen.inspect}"
    assert seen.uniq.size > 1, "fallback never moved off one entry: #{seen.inspect}"
  end

  # Solid Cache's failsafe only swallows its own transient errors, and nothing in
  # the panel chain rescues -- an unswallowed one would blank the screen.
  test "a cache that raises still moves the slide on" do
    seen = with_cache(raising_store) { 20.times.map { Display::Rotation.next_index("panel", size: 4) } }

    assert seen.all? { |index| (0...4).cover?(index) }, "fallback returned an out-of-range index: #{seen.inspect}"
    assert seen.uniq.size > 1, "fallback never moved off one entry: #{seen.inspect}"
  end

  private

  # The suite has no mocking library, so the store is swapped for a real one.
  def with_cache(store)
    original = Rails.cache
    Rails.cache = store
    yield
  ensure
    Rails.cache = original
  end

  def with_null_cache(&)
    with_cache(ActiveSupport::Cache::NullStore.new, &)
  end

  def raising_store
    Class.new(ActiveSupport::Cache::NullStore) do
      def increment(*, **)
        raise ActiveRecord::StatementInvalid, "solid_cache_entries is gone"
      end
    end.new
  end
end
