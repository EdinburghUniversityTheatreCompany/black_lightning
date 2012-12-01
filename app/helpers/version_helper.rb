module VersionHelper
  def version
    begin
      return 'Website Version: ' + File.read("version")
    rescue
    end
  end
end