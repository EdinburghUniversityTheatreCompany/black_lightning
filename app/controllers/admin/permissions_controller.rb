##
# The controller for setting permissions.
##
class Admin::PermissionsController < AdminController
  authorize_resource
  before_action :set_models_and_roles
  ##
  # Shows a grid for selecting permissions for each role.
  ##
  def grid
    @title = 'Permissions'
    @models.sort_by!(&:name)

    @actions = %w[read create update delete manage]
  end

  ##
  # Takes the data posted from the grid and sets the permissions.
  ##
  def update_grid
    @roles.includes(:permissions).each do |role|
      models = params[role.name]

      (@models.map(&:name) + @miscellaneous_permission_subject_classes.keys).uniq.each do |model_name|
        actions = models[model_name]&.keys if models
        actions ||= []

        Admin::Permission.update_permission(role, model_name, actions)
      end
    end

    redirect_to admin_permissions_url
  end

  private
  
  def set_models_and_roles
    @miscellaneous_permission_subject_classes = {
      'Admin::StaffingJob' => { 'sign_up_for' => 'Sign Up For Staffing' },
      'MarketingCreative::Profile' => { 'approve' => 'Approve or Reject Marketing Creative Profiles' },
      'backend' => { 'access' => 'Access Backend' },
      'reports' => { 'read' => 'Read Reports' },
      'User' => { 'view_shows_and_bio' => 'View the public part of the user profile (Bio, avatar, and shows)' },
      'Event' => { 'add_non_members' => 'Add non-members to events, mainly for archiving purposes' },
    }

    @models = (ApplicationRecord.descendants + [Admin::Debt, Season, Doorkeeper::Application] - [MarketingCreatives::CategoryInfo]).uniq

    role_exclude = ['admin', 'Proposal Checker']
    @roles = Role.includes(:permissions).where.not(name: role_exclude).all.left_joins(:permissions).group(:id).order('COUNT(admin_permissions.id) DESC')
  end
end
