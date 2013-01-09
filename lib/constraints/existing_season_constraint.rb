class ExistingSeasonConstraint
  def initialize
    @season_slugs = Season.all.map { |s| s.slug }
  end

  def matches?(request)
    @season_slugs.include?(request.url.split('/').last)
  end
end