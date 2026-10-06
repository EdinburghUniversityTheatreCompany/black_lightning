##
# Defines the abilities for each user. See CanCanCan documentation for more details.
#
# It reads the Admin::Permission model in the database to find if a user can do something.
###########
# WARNING #
###########
# Prefer hash conditions to blocks: a block alone breaks accessible_by unless you also pass a raw
# SQL string (can :action, Model, "sql_condition" do |record| ... end). A hash plus a block raises
# CanCan::BlockAndConditionsError.
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

    if user&.admin?
      ##############################################
      #              ADMIN PERMISSIONS             #
      ##############################################
      #        (Leave at the top like this)        #
      ##############################################
      can :manage, :all

      cannot :manage, Complaint
      can :create, Complaint

      # Do not allow admins to add non members to event by default to avoid cluttering their select boxes.
      # They can give themselves a role with the permission enabled if they want it.
      cannot :add_non_members, Event

      # Can view all the tests, except for the access_denied action, because that is the point.
      cannot :access_denied, :tests

      # Can view the error details on the error page.
      can :view_details, :errors

      # Even admins cannot advance-review unless the grid grants it.
      cannot :advance_review, :proposals

      # The grid goes first so the proposal rules take precedence.
      set_permissions_based_on_grid user

      proposal_permissions user

      return
    end

    alias_action :reject, :mark_successful, :mark_unsuccessful, :reset_status, to: :approve
    # Closing an opportunity just edits its expiry date.
    alias_action :close, to: :update
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

    can :read, Company

    # Have a specific view_shows_and_bio permission because it is a bad idea to give normal users full :read permission for users.
    can :view_shows_and_bio, User, public_profile: true

    # Even though users should not be able to sign up when they have a profile, that authorisation is handled by the controller.
    # This way we can show a more appropriate error message.
    can [ :sign_up, :create ], MarketingCreatives::Profile
    # Only people with explicit permission can do new. Create is an alias for new, so it has to be explicitly disallowed.
    cannot :new, MarketingCreatives::Profile

    # Everyone can create a complaint.
    can [ :create ], Complaint

    # Logged-out external submitters too; submissions stay unapproved until reviewed.
    can :create, Opportunity

    can :show, Admin::EditableBlock, admin_page: false
    can :show, Admin::EditableBlock, admin_page: nil

    can_show_files_at 2

    can :read, Review, event: { is_public: true }

    # Stop if the user is not logged in.
    return if user.nil?

    # All users can edit and see themselves.
    # All users can consent for themselves.
    can %I[show debt_status update edit consent], User, id: user.id
    # All users can autocomplete all users
    can :autocomplete, User

    # Because otherwise you also cannot read the proposals due to the url structure.
    can :read, Admin::Proposals::Call

    can %I[read answer set_answers], Admin::Questionnaires::Questionnaire, users: { id: user.id }

    can :read, Admin::Feedback, show: { users: { id: user.id } }

    team_member_roles_that_can_update_shows = [ "Director", "Producer", "Co-Producer", "Assistant Producer" ]
    team_member_roles_that_can_update_shows.each do |role|
      can %I[read update], Show, team_members: { position: role, user_id: user.id }
      can %I[read create update delete], Review, event: { team_members: { position: role, user_id: user.id } }
    end

    can :read, Admin::MaintenanceDebt, user_id: user.id
    can :read, Admin::StaffingDebt, user_id: user.id
    # Only grant the :show action for Admin::Debt so that normal users do not have access to the index page which is useless for them.
    can :show, Admin::Debt, id: user.id
    can :read, MaintenanceCredit, user_id: user.id

    can %I[read update], Opportunity, creator_id: user.id

    # Not indexing, because the index of profiles should only be visible to certain people.
    can :show, MarketingCreatives::Profile, approved: true
    can :read, MarketingCreatives::CategoryInfo, profile: { approved: true }

    if user.marketing_creatives_profile.present?
      can %i[show edit update reject], MarketingCreatives::Profile, id: user.marketing_creatives_profile.id
      can :read, MarketingCreatives::CategoryInfo, profile: user.marketing_creatives_profile
    end

    set_permissions_based_on_grid(user)

    proposal_permissions user

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
    can :manage, %i[duplicate membership_import user_import] if can? :absorb, User

    can :check_debt, Admin::Debt if can?(:index, Admin::Debt)

    can :debt_overview, Event if can?(:create, Admin::MaintenanceDebt) || can?(:create, Admin::StaffingDebt)

    # Stops `can :manage, Role` from covering add_user and remove_user.
    cannot [ :add_user, :remove_user ], Role

    # All users with role X control the roles which have X as a parent.
    child_roles_this_user_can_manage = Role.joins(:parents).where(parents_roles: { id: user.roles }).pluck(:id)

    can [ :read, :update, :add_user, :remove_user ], Role, id: child_roles_this_user_can_manage

    # All logged-in users can view trained roles (e.g. DM Trained, Bar Trained).
    can [ :read ], Role, id: Role.trained.pluck(:id)


    if can?(:access, :backend)
      can :show, Admin::EditableBlock
      can_show_files_at 1
    end
  end

  # Proposal rules for admins and users alike. They come after set_permissions_based_on_grid so
  # the grid cannot override them and can?(:review, :proposals) is already true.
  def proposal_permissions(user)
    # No one (even admins) should be able to read proposals before the submission deadline has passed.
    cannot :manage, Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current..DateTime::Infinity.new }

    can :about, Admin::Proposals::Proposal

    can :create, Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current..DateTime::Infinity.new }

    # Users always see the proposals they are on.
    can :read, Admin::Proposals::Proposal, users: { id: user.id }
    # Approved proposals, current or archived, are visible to all.
    can :read, Admin::Proposals::Proposal,
      status: [ :approved, :successful, :unsuccessful ].map { |s| Admin::Proposals::Proposal.statuses[s] }

    can [ :update, :unwithdraw ], Admin::Proposals::Proposal, users: { id: user.id }, call: { editing_deadline: DateTime.current..DateTime::Infinity.new }

    # Withdrawing stays open until a terminal status (see below).
    can :withdraw, Admin::Proposals::Proposal, users: { id: user.id }

    # `review proposals` (Committee, Proposal Checker): every proposal past its submission
    # deadline. Proposal is not a grid model row because its rules are time-based.
    if can?(:review, :proposals)
      can :read, Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current.advance(years: -100)..DateTime.current }
      can :index, Admin::Proposals::Proposal
    end

    # Prod Man is able to help out with proposals after the submission deadline.
    if can?(:manage_after_submission, :proposals)
      can :manage, Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current.advance(years: -100)..DateTime.current }
    end

    cannot [ :approve, :reject, :mark_successful, :mark_unsuccessful ], Admin::Proposals::Proposal, withdrawn: true
    cannot [ :approve, :reject, :mark_successful, :mark_unsuccessful ], Admin::Proposals::Proposal, call: { submission_deadline: DateTime.current..DateTime::Infinity.new }

    cannot :withdraw, Admin::Proposals::Proposal,
      status: [ :rejected, :unsuccessful, :successful ].map { |s| Admin::Proposals::Proposal.statuses[s] }

    # `advance review` (generally Bus Man, Set Man, Prod Man, Secretary): proposals before the
    # submission deadline. Contentious, but company consensus is positive.
    if can?(:advance_review, :proposals)
      can :read, Admin::Proposals::Proposal
    end
  end

  private

  # Attachments, videos and pictures at this access level, wherever the item they belong to
  # (if any) can be shown.
  def can_show_files_at(level)
    [ Attachment, VideoLink, Picture ].each do |file_class|
      can :show, file_class, "access_level = #{level}" do |file|
        file.access_level == level && ((item = file.authorizable_item).nil? || can?(:show, item))
      end
    end
  end
end
