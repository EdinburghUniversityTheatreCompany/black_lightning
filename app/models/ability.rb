##
# Defines the abilities for each user. See CanCanCan documentation for more details.
#
# It reads the Admin::Permission model in the database to find if a user can do something.
###########
# WARNING #
###########
# Please do not define permissions using blocks. Use the hash notation.
# Using blocks breaks load_and_authorize_resource unless you define the SQL query as well.
# See: https://github.com/CanCanCommunity/cancancan/wiki/Defining-Abilities and the separate pages for the different kinds of definitions.
#
# When you add a permission, please add a test for it, even if it is obvious what it does.
##

class Ability
  include CanCan::Ability

  # Define the permissions for a user.
  def initialize(user)
    # The 4 CRUD actions are automatically aliased to the 7 RESTful actions.
    # :read -> :show, :index
    # :create -> :new, :create
    # :update -> :edit, :update
    # :delete is not mapped to :destroy, that's done manually.
    # :manage -> every action

    if user&.has_role?(:admin)
      ##############################################
      #              ADMIN PERMISSIONS             #
      ##############################################
      #        (Leave at the top like this)        #
      ##############################################
      can :manage, :all
      return
    end

    # If you can approve something, you can also reject it.
    alias_action :reject, to: :approve
    # Alias grid to read
    alias_action :grid, to: :read
    alias_action :guidelines, to: :read
    alias_action :debt_status, to: :read
    # Alias :delete to :destroy because they're easy to mix up and
    # because the current permission actions use :delete and the controller actions use :destroy
    alias_action :destroy, to: :delete

    # You must also update opportunity.rb when editing this.
    can :read, Opportunity, approved: true, expiry_date: Time.now..DateTime::Infinity.new

    # Guests can see all venues.
    can :read, Venue

    # Guests can see public events, news, and user profiles.
    can :read, News, show_public: true
    can :read, Event, is_public: true
    can :view_public_profile, User, public_profile: true

    # Stop if the user is not logged in.
    return if user.nil?
    # All users can edit, see and destroy themselves.
    can %I[show debt_status update edit destroy], User, id: user.id

    # People can see debt status for users on proposals they are on.
    # It is disabled because it is currently more efficient to just do this on the proposal show thing.
    #proposals_with_current_user = Admin::Proposals::Proposal.joins(:team_members).where('team_members.user_id = ?', user.id)
    #shared_proposal_user_ids = TeamMember.where(teamwork: proposals_with_current_user).pluck(:user_id)

    #can :debt_status, User, id: shared_proposal_user_ids




    can %I[read answer], Admin::Questionnaires::Questionnaire, users: { id: user.id }

    can :read, Admin::Feedback, show: { users: { id: user.id } }

    team_member_roles_that_can_update_shows = %w[Director Producer]
    team_member_roles_that_can_update_shows.each do |role|
      can %I[read update], Show, team_members: { position: role, user_id: user.id }
    end

    can :read, Admin::MaintenanceDebt, user_id: user.id
    can :read, Admin::StaffingDebt, user_id: user.id
    # Only grant the :show action for Admin::Debt so that normal users do not have access to the index page which is useless for them.
    can :show, Admin::Debt, id: user.id

    can %I[read update], Opportunity, creator_id: user.id

    # Grant the user permissions based on the grid.
    permissions = user.roles.includes(:permissions).flat_map(&:permissions).uniq
    permissions.each do |permission|
      # Some permissions are not associated with a class, but just with a symbol, such as :backend.
      begin
        subject_class = permission.subject_class.constantize
      rescue NameError
        subject_class = permission.subject_class.to_sym
      ensure
        can permission.action.to_sym, subject_class
      end
    end
  end
end
