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
    @title = "Permissions"
    @models.sort_by!(&:name)

    @actions = %w[read create update delete manage]
  end

  def role_grid
    @role = Role.includes(:permissions).find(params[:id])
    if Admin::Permission::EXCLUDED_ROLES.include?(@role.name)
      redirect_to admin_role_path(@role), alert: "Permissions for #{@role.name} are not managed here."
      return
    end
    @roles = [ @role ]
    @actions = %w[read create update delete manage]
    @title = "Permissions — #{@role.name}"
    @models.sort_by!(&:name)
  end

  def update_role_grid
    @role = Role.includes(:permissions).find(params[:id])
    if Admin::Permission::EXCLUDED_ROLES.include?(@role.name)
      redirect_to admin_role_path(@role), alert: "Permissions for #{@role.name} are not managed here."
      return
    end
    @roles = [ @role ]

    models = params["[#{@role.name}]"]
    if models
      (@models.map(&:name) + @miscellaneous_permission_subject_classes.keys).uniq.each do |model_name|
        actions = models[model_name]&.keys || []
        Admin::Permission.update_permission(@role, model_name, actions)
      end
    end

    redirect_to permissions_admin_role_url(@role)
  end

  ##
  # Takes the data posted from the grid and sets the permissions.
  ##
  def update_grid
    @roles.includes(:permissions).each do |role|
      models = params["[#{role.name}]"]

      # Skip roles that have no data in the submission. This prevents wiping
      # all permissions when the form is submitted before fully loading, or
      # when a role's checkboxes are all unchecked (HTML checkboxes only
      # submit values when checked).
      next unless models

      (@models.map(&:name) + @miscellaneous_permission_subject_classes.keys).uniq.each do |model_name|
        actions = models[model_name]&.keys || []

        Admin::Permission.update_permission(role, model_name, actions)
      end
    end

    redirect_to admin_permissions_url
  end

  private

  def set_models_and_roles
    @miscellaneous_permission_subject_classes = {
      "Admin::StaffingJob" => { "sign_up_for" => "Sign Up For Staffing" },
      "MarketingCreative::Profile" => { "approve" => "Approve or Reject Marketing Creative Profiles" },
      "backend" => { "access" => "Access Backend" },
      "reimbursements" => { "access" => "Access the Reimbursements portal (submit and track expenses)" },
      "reports" => { "read" => "Read Reports" },
      "User" => { "view_shows_and_bio" => "View the public part of the user profile (Bio, avatar, and shows)" },
      "Event" => { "add_non_members" => "Add non-members to events, mainly for archiving purposes" }
    }

    @models = (ApplicationRecord.descendants + [ Admin::Debt, Season, Doorkeeper::Application ] - [ MarketingCreatives::CategoryInfo, Admin::Proposals::Proposal, OpportunityRole ]).uniq

    role_exclude = Admin::Permission::EXCLUDED_ROLES
    @roles = Role.includes(:permissions).where.not(name: role_exclude).all.left_joins(:permissions).group(:id).order("COUNT(admin_permissions.id) DESC")
  end
end
