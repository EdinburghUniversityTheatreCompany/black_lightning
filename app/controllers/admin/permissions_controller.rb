##
# The controller for setting permissions.
##
class Admin::PermissionsController < AdminController
  ACTIONS = %w[read create update delete manage].freeze

  authorize_resource
  before_action :set_models_and_roles
  before_action :load_managed_role, only: %i[role_grid update_role_grid]
  ##
  # Shows a grid for selecting permissions for each role.
  ##
  def grid
    @title = "Permissions"
  end

  def role_grid
    @roles = [ @role ]
    @title = "Permissions: #{@role.name}"
  end

  def update_role_grid
    save_grid(@role)

    redirect_to permissions_admin_role_url(@role)
  end

  ##
  # Takes the data posted from the grid and sets the permissions.
  ##
  def update_grid
    @roles.each { |role| save_grid(role) }

    redirect_to admin_permissions_url
  end

  private

  def load_managed_role
    @role = Role.includes(:permissions).find(params[:id])
    return unless Admin::Permission::EXCLUDED_ROLES.include?(@role.name)

    redirect_to admin_role_path(@role), alert: "Permissions for #{@role.name} are not managed here."
  end

  def save_grid(role)
    models = params["[#{role.name}]"]
    # Skip roles absent from the post: unchecked boxes submit nothing, so a partial
    # load would wipe the role.
    return unless models

    (@models.map(&:name) + @miscellaneous_permission_subject_classes.keys).uniq.each do |model_name|
      Admin::Permission.update_permission(role, model_name, models[model_name]&.keys || [])
    end
  end

  def set_models_and_roles
    @actions = ACTIONS
    @miscellaneous_permission_subject_classes = {
      "Admin::StaffingJob" => { "sign_up_for" => "Sign Up For Staffing" },
      "MarketingCreative::Profile" => { "approve" => "Approve or Reject Marketing Creative Profiles" },
      "backend" => { "access" => "Access Backend" },
      "committee" => { "access" => "Access the committee resources page" },
      # Misc-only subjects must be symbols, never a class name: a grid save calls update_permission
      # with only the actions listed here, which deleted the stored manage rows for
      # Admin::Proposals::Proposal on 2026-05-08.
      "proposals" => { "manage_after_submission" => "Manage Proposals (after the submission deadline)",
                       "review" => "Review proposals (after the submission deadline)",
                       "advance_review" => "Review proposals (advance of the submission deadline, temporary)" },
      "reimbursements" => { "access" => "Access the Reimbursements portal (submit and track expenses)" },
      "reimbursements_finance" => { "manage" => "Manage reimbursements finance (People, Review, Batches, Reconcile)" },
      "reports" => { "read" => "Read Reports" },
      # :manage matches any action, so granting manage implies read.
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
                  Climate::Sensor, Climate::Reading, EventOccurrence ]).uniq.sort_by(&:name)

    role_exclude = Admin::Permission::EXCLUDED_ROLES
    @roles = Role.includes(:permissions).where.not(name: role_exclude).left_joins(:permissions).group(:id).order("COUNT(admin_permissions.id) DESC")
  end
end
