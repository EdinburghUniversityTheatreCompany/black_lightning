module VersionHistoryHelper
  def version_author_name(version)
    return "System" if version.whodunnit.blank?

    user = User.find_by(id: version.whodunnit)
    user ? user_link(user, false) : "User ##{version.whodunnit} (deleted)"
  end
end
