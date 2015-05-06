class ExistingSeasonConstraint
  def initialize
    if Season.table_exists?
      @season_slugs = Season.select(:slug).collect(&:slug)
    else
      @season_slugs = nil
    end
  end

  def matches?(request)
    return false if @season_slugs.nil?

    @season_slugs.include?(request.url.split('/').last)
  end
end
