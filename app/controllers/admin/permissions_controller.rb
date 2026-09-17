##
# The controller for setting permissions.
##
class Admin::PermissionsController < AdminController
  authorize_resource
  before_action :set_models_and_groups
  ##
  # Shows a grid for selecting permissions for each group.
  ##
  def grid
    @title = "Permissions"
    @models.sort_by!(&:name)

    @actions = %w[read create update delete manage]
  end

  def group_grid
    @group = Group.includes(:permissions).find(params[:id])
    if Admin::Permission::EXCLUDED_ROLES.include?(@group.name)
      redirect_to admin_group_path(@group), alert: "Permissions for #{@group.name} are not managed here."
      return
    end
    @groups = [ @group ]
    @actions = %w[read create update delete manage]
    @title = "Permissions: #{@group.name}"
    @models.sort_by!(&:name)
  end

  def update_group_grid
    @group = Group.includes(:permissions).find(params[:id])
    if Admin::Permission::EXCLUDED_ROLES.include?(@group.name)
      redirect_to admin_group_path(@group), alert: "Permissions for #{@group.name} are not managed here."
      return
    end
    @groups = [ @group ]

    models = params["[#{@group.name}]"]
    if models
      (@models.map(&:name) + @miscellaneous_permission_subject_classes.keys).uniq.each do |model_name|
        actions = models[model_name]&.keys || []
        Admin::Permission.update_permission(@group, model_name, actions)
      end
    end

    redirect_to permissions_admin_group_url(@group)
  end

  ##
  # Takes the data posted from the grid and sets the permissions.
  ##
  def update_grid
    @groups.includes(:permissions).each do |group|
      models = params["[#{group.name}]"]

      # Skip roles that have no data in the submission. This prevents wiping
      # all permissions when the form is submitted before fully loading, or
      # when a role's checkboxes are all unchecked (HTML checkboxes only
      # submit values when checked).
      next unless models

      (@models.map(&:name) + @miscellaneous_permission_subject_classes.keys).uniq.each do |model_name|
        actions = models[model_name]&.keys || []

        Admin::Permission.update_permission(group, model_name, actions)
      end
    end

    redirect_to admin_permissions_url
  end

  private

  def set_models_and_groups
    @miscellaneous_permission_subject_classes = {
      "Admin::StaffingJob" => { "sign_up_for" => "Sign Up For Staffing" },
      "MarketingCreative::Profile" => { "approve" => "Approve or Reject Marketing Creative Profiles" },
      "backend" => { "access" => "Access Backend" },
      "committee" => { "access" => "Access the committee resources page" },
      # A symbol subject on purpose, not "Admin::Proposals::Proposal": that class is excluded from
      # the model rows (its read rules are time-based, see Ability), and a miscellaneous-only entry
      # named after a class makes every save call update_permission for it with just the actions
      # offered here — deleting the read/update/manage rows stored before 2026-05-08, which is how
      # non-admins approve proposals. Any misc-only subject must be a symbol for the same reason.
      "proposals" => { "review" => "Review proposals (read every proposal after its call's deadline)",
                       "advance_review" => "Review proposals advance of the submission deadline (temporary)" },
      "reimbursements" => { "access" => "Access the Reimbursements portal (submit and track expenses)" },
      "reimbursements_finance" => { "manage" => "Manage reimbursements finance (People, Review, Batches, Reconcile)" },
      "reports" => { "read" => "Read Reports" },
      # :manage matches any action in CanCan, so granting manage implies read.
      "climate" => { "read" => "View the climate monitor (crypt temperature / humidity charts)",
                     "manage" => "Configure climate sensors and import readings" },
      "User" => { "view_shows_and_bio" => "View the public part of the user profile (Bio, avatar, and shows)" },
      "Event" => { "add_non_members" => "Add non-members to events, mainly for archiving purposes" }
    }

    @models = (ApplicationRecord.descendants + [ Admin::Debt, Season, Doorkeeper::Application ] - [ MarketingCreatives::CategoryInfo, Admin::Proposals::Proposal, OpportunityRole, Reimbursements::BatchAttempt, Reimbursements::OwnerEndorsement,
                  Reimbursements::Person, Reimbursements::PaymentDetails, Reimbursements::Budget,
                  Reimbursements::BudgetOwner, Reimbursements::BudgetForecast, Reimbursements::BudgetUpdate,
                  Reimbursements::Area, Reimbursements::AreaOwner,
                  Reimbursements::Expense, Reimbursements::Batch, Reimbursements::EusaActual,
                  Reimbursements::FinancialYear, Reimbursements::CostCentre, Reimbursements::NominalCode,
                  Climate::Sensor, Climate::Reading, EventOccurrence ]).uniq

    role_exclude = Admin::Permission::EXCLUDED_ROLES
    @groups = Group.includes(:permissions).where.not(name: role_exclude).all.left_joins(:permissions).group(:id).order("COUNT(admin_permissions.id) DESC")
  end
end
