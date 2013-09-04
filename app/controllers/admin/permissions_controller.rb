##
# The controller for setting permissions.
##
class Admin::PermissionsController < AdminController

  ##
  # Shows a grid for selecting permissions for each role.
  ##
  def grid
    authorize!(:read, Admin::Permission)

    role_exclude = ['admin']
    @roles  = ::Role.includes(:permissions).where("name NOT IN (?)", role_exclude).all

    Rails.application.eager_load!
    @models = ::ActiveRecord::Base.descendants
    @title = "Permissions"
  end

  ##
  # Takes the data posted from the grid and sets the permissions.
  ##
  def update_grid
    authorize!(:edit, Admin::Permission)

    role_exclude = ['admin']
    @roles  = ::Role.where("name NOT IN (?)", role_exclude)

    Rails.application.eager_load!
    @models = ::ActiveRecord::Base.descendants

    @roles.each do |role|
      @models.each do |model|
        _models = params[role.name]

        actions = _models[model.name] if _models
        actions ||= []

        Admin::Permission.update_permission(role, model.name, actions)
      end

      other_permissions = ['backend', 'reports']

      other_permissions.each do |model|
        _models = params[role.name]

        actions = _models[model] if _models
        actions ||= []

        Admin::Permission.update_permission(role, model, actions)
      end
    end

    return redirect_to :admin_permissions
  end

end
