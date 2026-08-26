module Display
  # A cursor that moves on one place every time it is read.
  #
  # Anthias re-fetches each playlist URL every few minutes, so a panel that picks
  # the same row every time shows one frame all day. State lives in the cache
  # rather than the URL -- these URLs are typed into a Pi by hand and must keep
  # working unchanged -- and not in the session, which a kiosk browser nobody
  # signs in to cannot be relied on for.
  class Rotation
    # Outlives a day of playback; yesterday's cursor then expires by itself.
    TTL = 2.days

    # Keyed by date: the rotation varies within a day, not which entry opens it.
    def self.next_index(name, size:, on: Date.current)
      return 0 if size <= 1

      position = advance(name, on)

      # The cache could not answer: a null store, or a cache database that is
      # down. Random repeats sometimes, which still beats standing on the first
      # entry for the rest of the day.
      return rand(size) if position.nil?

      (position - 1) % size
    end

    # increment initialises a missing key to 1, so the first read is index 0.
    # Solid Cache's own failsafe only swallows its transient errors, and nothing
    # in the panel chain rescues: without this the screen would go blank on a
    # cache the rotation is only using to decide which of two posters to show.
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
