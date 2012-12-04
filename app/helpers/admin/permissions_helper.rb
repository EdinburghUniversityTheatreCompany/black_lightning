module Admin::PermissionsHelper
  def permissions
    begin
      ::Admin::Permission
    rescue
      false
    end
  end
end
