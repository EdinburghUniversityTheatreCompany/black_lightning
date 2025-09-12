module VersionHelper
  def version
    begin
      File.read("version")
    rescue
      "Not found"
    end
  end
end
