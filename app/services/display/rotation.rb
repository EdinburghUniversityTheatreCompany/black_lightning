module Display
  # A cursor that moves on one place every time it is read, so a panel that
  # Anthias re-fetches every few minutes does not show one frame all day. State is
  # in the cache, not the URL (typed into a Pi by hand, must keep working
  # unchanged) or the session (a kiosk has none).
  class Rotation
    # Outlives a day of playback; yesterday's cursor then expires by itself.
    TTL = 2.days

    # Keyed by date: the rotation varies within a day, not which entry opens it.
    def self.next_index(name, size:, on: Date.current)
      return 0 if size <= 1

      position = advance(name, on)

      # The cache could not answer (null store, or database down). Random repeats
      # sometimes, which still beats standing on the first entry all day.
      return rand(size) if position.nil?

      (position - 1) % size
    end

    # increment initialises a missing key to 1, so the first read is index 0.
    # Solid Cache's failsafe swallows only its own transient errors and nothing in
    # the panel chain rescues, so without this a cache fault would blank the screen.
    def self.advance(name, on)
      Rails.cache.increment(key(name, on), 1, expires_in: TTL)
    rescue StandardError => e
      Rails.error.report(e, handled: true, severity: :warning)
      nil
    end
    private_class_method :advance

    def self.key(name, on)
      "display/rotation/#{name}/#{on.iso8601}"
    end
    private_class_method :key
  end
end
