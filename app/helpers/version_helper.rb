module VersionHelper
  def version
    begin
      return File.read("version")
    rescue
    end
  end
end