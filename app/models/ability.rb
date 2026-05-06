##
# Defines the abilities for each user. See CanCanCan documentation for more details.
#
# It reads the Admin::Permission model in the database to find if a user can do something.
###########
# WARNING #
###########
# Prefer hash conditions over block. Hash conditions work with load_and_authorize_resource
# and accessible_by (SQL generation) automatically. Blocks alone break SQL generation,
# which means you need to pass a raw SQL string as the conditions argument instead of
# a hash: can :action, Model, "sql_condition" do |record| ... end
# Combining a hash with a block raises CanCan::BlockAndConditionsError.
# See: https://github.com/CanCanCommunity/cancancan/wiki/Defining-Abilities and the separate pages for the different kinds of definitions.
#
# When you add a permission, please add a test for it, even if it is obvious what it does.
##

class Ability
  include CanCan::Ability

  def set_permissions_based_on_grid(user)
    permissions = user.roles.includes(:permissions).flat_map(&:permissions).uniq
    permissions.each do |permission|
      # Some permissions are not associated with a class, but just with a symbol, such as :backend.
      begin
        subject_class = permission.subject_class.constantize
      rescue NameError
        subject_class = permission.subject_class.to_sym
      ensure
        action = permission.action.to_sym
        can action, subject_class

        # This line is ugly, but I cannot think of another way apart from putting CategoryInfo's in the grid as well, which would be confusing.
        can :read, MarketingCreatives::CategoryInfo if subject_class == MarketingCreatives::Profile && (action == :read || action == :show)
      end
    end
  end

  # Define the permissions for a user.
  def initialize(user)
    # The 4 CRUD actions are automatically aliased to the 7 RESTful actions.
    # :read -> :show, :index
    # :create -> :new, :create
    # :update -> :edit, :update
    # :delete is not mapped to :destroy, that's done manually.
    # :manage -> every action

    if user&.has_role?("Admin")
      ##############################################
      #              ADMIN PERMISSIONS             #
      ##############################################
      #        (Leave at the top like this)        #
      ##############################################
      can :manage, :all

      # Even admins should not be able to read proposals before the submission deadline has been passed.
      cannot :manage, Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current..DateTime::Infinity.new }

      can [ :update, :read, :delete ], Admin::Proposals::Proposal, users: { id: user.id }
      can [ :index, :create ], Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current..DateTime::Infinity.new }

      cannot :manage, Complaint
      can :create, Complaint

      # Do not allow admins to add non members to event by default to avoid cluttering their select boxes.
      # They can give themselves a role with the permission enabled if they want it.
      cannot :add_non_members, Event

      # Can view all the tests, except for the access_denied action, because that is the point.
      cannot :access_denied, :tests

      # Can view the error details on the error page.
      can :view_details, :errors

      # To override restrictions if the admin has the appropriate role.
      set_permissions_based_on_grid(user)

      return
    end

    # If you can approve something, you can also reject it, and mark proposals successful/unsuccessful.
    alias_action :reject, :mark_successful, :mark_unsuccessful, to: :approve
    # Alias grid to read
    alias_action :grid, to: :read
    alias_action :debt_status, to: :read
    # Alias :delete to :destroy because they're easy to mix up and
    # because the current permission actions use :delete and the controller actions use :destroy
    alias_action :destroy, to: :delete

    # You must also update opportunity.rb when editing this.
    can :read, Opportunity, approved: true, expiry_date: Time.current..DateTime::Infinity.new

    # Guests can see all venues.
    can [ :read, :map ], Venue

    # Guests can see public events, news, and user profiles.
    can :read, News, show_public: true
    can :read, Event, is_public: true

    # Guests can see all Event Tags.
    can :read, EventTag

    # Have a specific view_shows_and_bio permission because it is a bad idea to give normal users full :read permission for users.
    can :view_shows_and_bio, User, public_profile: true

    # Even though users should not be able to sign up when they have a profile, that authorisation is handled by the controller.
    # This way we can show a more appropriate error message.
    can [ :sign_up, :create ], MarketingCreatives::Profile
    # Only people with explicit permission can do new. Create is an alias for new, so it has to be explicitly disallowed.
    cannot :new, MarketingCreatives::Profile

    # Everyone can create a complaint.
    can [ :create ], Complaint

    can :show, Admin::EditableBlock, admin_page: false
    can :show, Admin::EditableBlock, admin_page: nil

    can :show, Attachment, "access_level = 2" do |attachment|
      attachment.access_level == 2 &&
        ((item = attachment.authorizable_item).nil? || can?(:show, item))
    end
    can :show, VideoLink, "access_level = 2" do |video_link|
      video_link.access_level == 2 &&
        ((item = video_link.authorizable_item).nil? || can?(:show, item))
    end
    can :show, Picture, "access_level = 2" do |picture|
      picture.access_level == 2 &&
        ((item = picture.authorizable_item).nil? || can?(:show, item))
    end

    can :read, Review, event: { is_public: true }

    # Stop if the user is not logged in.
    return if user.nil?

    # All logged-in users can view trained roles (e.g. DM Trained, Bar Trained).
    can [ :read, :update ], Role, id: Role.trained.pluck(:id) + user.roles.collect { |role| role.children }.flatten.pluck(:id)

    # All users can edit and see themselves.
    # All users can consent for themselves.
    can %I[show debt_status update edit consent], User, id: user.id
    # All users can autocomplete all users
    can :autocomplete, User

    # People can see debt status for users on proposals they are on.
    # It is disabled because it is currently more efficient to just do this on the proposal show thing.
    # proposals_with_current_user = Admin::Proposals::Proposal.joins(:team_members).where('team_members.user_id = ?', user.id)
    # shared_proposal_user_ids = TeamMember.where(teamwork: proposals_with_current_user).pluck(:user_id)

    # can :debt_status, User, id: shared_proposal_user_ids

    # Give committee and proposal viewers the read permission using the grid.
    # Show all proposals that an user is on, even if they are not approved / the submission deadline has not been reached.
    can :read, Admin::Proposals::Proposal, users: { id: user.id }
    # Users can see all approved proposals after the deadline and once the call has closed. Whether current or archived.
    can :read, Admin::Proposals::Proposal, status: [ :approved, :successful, :unsuccessful ]

    if user.has_role?("Proposal Checker") || user.has_role?("Committee")
      # If the user is a proposal checker, they should be able to read any proposal after the submission deadline, no matter if they are approved, rejected, or awaiting, after the submission deadline.
      can :read, Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current.advance(years: -100)..DateTime.current }

      # They should also be able to index every proposal.
      can :index, Admin::Proposals::Proposal
    end

    can :create, Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current..DateTime::Infinity.new }

    can :update, Admin::Proposals::Proposal, users: { id: user.id }, call: { editing_deadline: DateTime.current..DateTime::Infinity.new }

    # Everyone can read the about page.
    can :about, Admin::Proposals::Proposal

    # Because otherwise you also cannot read the proposals due to the url structure.
    can :read, Admin::Proposals::Call

    can %I[read answer set_answers], Admin::Questionnaires::Questionnaire, users: { id: user.id }

    can :read, Admin::Feedback, show: { users: { id: user.id } }

    team_member_roles_that_can_update_shows = %w[Director Producer Co-Producer Assistant Producer]
    team_member_roles_that_can_update_shows.each do |role|
      can %I[read update], Show, team_members: { position: role, user_id: user.id }
      can %I[read create update delete], Review, event: { team_members: { position: role, user_id: user.id } }
    end

    can :read, Admin::MaintenanceDebt, user_id: user.id
    can :read, Admin::StaffingDebt, user_id: user.id
    # Only grant the :show action for Admin::Debt so that normal users do not have access to the index page which is useless for them.
    can :show, Admin::Debt, id: user.id
    # Users can see their own maintenance attendance, but not edit them.
    can :read, MaintenanceAttendance, user_id: user.id

    can %I[read update], Opportunity, creator_id: user.id

    # Not indexing, because the index of profiles should only be visible to certain people.
    can :show, MarketingCreatives::Profile, approved: true
    can :read, MarketingCreatives::CategoryInfo, profile: { approved: true }

    if user.marketing_creatives_profile.present?
      can %i[show edit update reject], MarketingCreatives::Profile, id: user.marketing_creatives_profile.id
      can :read, MarketingCreatives::CategoryInfo, profile: user.marketing_creatives_profile
    end

    set_permissions_based_on_grid(user)

    # Producers on future shows can use the bulk debt checker
    if TeamMember
         .joins("INNER JOIN events ON events.id = team_members.teamwork_id AND team_members.teamwork_type = 'Event'")
         .where(user_id: user.id)
         .where("events.type = 'Show'")
         .where("events.end_date >= ?", Date.current)
         .where("LOWER(team_members.position) LIKE ?", "%producer%")
         .exists?
      can :check_debt, Admin::Debt
    end

    # Users who can absorb users can also view and manage duplicates and imports
    can :manage, :duplicate if can? :absorb, User
    can :manage, :membership_import if can? :absorb, User
    can :manage, :user_import if can? :absorb, User

    # Anyone who can index debts via the grid can also use the debt checker
    can :check_debt, Admin::Debt if can?(:index, Admin::Debt)

    # Grant debt_overview access if user can create either type of debt
    can :debt_overview, Event if can?(:create, Admin::MaintenanceDebt) || can?(:create, Admin::StaffingDebt)

    # Explicitly exclude add_user and remove_user from :manage on Role
    # This prevents users with "can :manage, Role" from automatically being able to add/remove users
    cannot [ :add_user, :remove_user ], Role

    # Re-allow for admins (they should be able to add/remove users from any role)
    if user&.has_role?("Admin")
      can [ :add_user, :remove_user ], Role
    end

    can [ :add_user, :remove_user ], Role do |role|
      role&.parents.any? { |p| user&.has_role?(p) }
    end

    can :show, Admin::EditableBlock if can? :access, :backend

    if can?(:access, :backend)
      can :show, Attachment, "access_level = 1" do |attachment|
        attachment.access_level == 1 &&
          ((item = attachment.authorizable_item).nil? || can?(:show, item))
      end
    end

    if can?(:access, :backend)
      can :show, VideoLink, "access_level = 1" do |video_link|
        video_link.access_level == 1 &&
          ((item = video_link.authorizable_item).nil? || can?(:show, item))
      end
      can :show, Picture, "access_level = 1" do |picture|
        picture.access_level == 1 &&
          ((item = picture.authorizable_item).nil? || can?(:show, item))
      end
    end
  end
end
