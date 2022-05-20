require "#{Rails.root}/lib/constraints"

# The constraint is tested in the (non-admin) seasons controller test.
class Constraints::ExistingSeason
  def get_season_slugs
    if Season.table_exists?
      return Season.select(:slug).collect(&:slug)
    else
      # This is here because of issue #123
      # :nocov:
      p 'The table seasons does not exist'
      return nil
      #: nocov:
    end
  end

  def matches?(request)
    season_slugs = get_season_slugs
    return false if season_slugs.nil?

    return season_slugs.include?(request.url.split('/').last)
  end
end
