module WorkshopCounter
  def self.workshop_count
    Rails.cache.fetch("workshop_count", :expires_in => 15.minutes) do
      return Workshop.current.count
    end
  end
end