class Admin::PermissionsController < AdminController

  def grid
    @roles  = ::Role.all

    Rails.application.eager_load!
    @models = ::ActiveRecord::Base.descendants
  end

  def update_grid
    @roles  = ::Role.all

    Rails.application.eager_load!
    @models = ::ActiveRecord::Base.descendants

    @roles.each do |role|
      @models.each do |model|
        _models = params[role.name]
        next unless _models

        actions = _models[model.name]
        next unless actions

        existing_permissions = role.permissions.where({ :subject_class => model.name })

        if existing_permissions then
          existing_permissions.each do |perm|
            if not actions.include? perm.action then
              #The role no longer has this permission. Get rid
              perm.delete
            end
          end
        end

        actions.each do |action|
          if (not existing_permissions) or (not existing_permissions.find_by_action(action)) then
            #Try to add the role to the existing permission
            if permission = Admin::Permission.where({ :action => action, :subject_class => model.name }).first;
              permission.roles << role
            else
              permission = Admin::Permission.new
              permission.action = action[0]
              permission.subject_class = model.name
              permission.roles << role
            end

            permission.save
          end
        end

        role.save
      end
    end

    return redirect_to :admin_permissions
  end

end
