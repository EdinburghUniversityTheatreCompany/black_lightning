module VersionHelper
  def version
    return File.read('version')
  rescue
  end
end
