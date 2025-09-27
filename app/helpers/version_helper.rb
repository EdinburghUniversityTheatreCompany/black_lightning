module VersionHelper
  def version
    # Try Kamal environment variable first (git SHA from deployment)
    if ENV['KAMAL_VERSION'].present?
      return ENV['KAMAL_VERSION'][0,8]
    end

    # Final fallback
    "Unknown"
  end
end
