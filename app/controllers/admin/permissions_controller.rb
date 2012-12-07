class Admin::PermissionsController < AdminController

  def grid
    authorize!(:read, Admin::Permission)

    role_exclude = ['admin']
    @roles  = ::Role.where("name NOT IN (?)", role_exclude)

    Rails.application.eager_load!
    @models = ::ActiveRecord::Base.descendants
    @title = "Permissions"
  end

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

      other_permissions = ['backend']

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
