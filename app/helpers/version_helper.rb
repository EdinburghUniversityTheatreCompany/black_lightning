module VersionHelper
  def version
    begin
      return File.read('version')
    rescue
      return 'Not found'
    end
  end
end
