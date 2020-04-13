##
# The controller for setting permissions.
##
class Admin::PermissionsController < AdminController
  ##
  # Shows a grid for selecting permissions for each role.
  ##
  def grid
    @title = 'Permissions'
    authorize! :read, Admin::Permission

    @actions = %w[read create update delete manage]
    @roles = get_roles

    Rails.application.eager_load!
    @models = get_models
  end

  ##
  # Takes the data posted from the grid and sets the permissions.
  ##
  def update_grid
    authorize! :manage, Admin::Permission
    @roles = get_roles

    Rails.application.eager_load!
    @models = get_models

    @roles.each do |role|
      models = params[role.name]

      (@models.map(&:name) + @miscellaneous_permission_subject_classes.keys).uniq.each do |model_name|
        actions = models[model_name] if models
        actions ||= []

        Admin::Permission.update_permission(role, model_name, actions)
      end
    end

    return redirect_to :admin_permissions
  end

  def get_roles
    role_exclude = ['admin']
    return ::Role.includes(:permissions).where('name NOT IN (?)', role_exclude).all
  end

  def get_models
    @miscellaneous_permission_subject_classes = {
      'Admin::StaffingJob' => { 'sign_up_for' => 'Sign Up For Staffing' },
      'backend' => { 'access' => 'Access Backend' },
      'reports' => { 'read' => 'Read Reports' }
    }

    models = ApplicationRecord.descendants + [Admin::Debt]
    return models.sort_by(&:name)
  end
end
