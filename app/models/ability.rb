class Ability
  include CanCan::Ability

  def initialize(user)
    # Define abilities for the passed in user here. For example:
    #
    #   user ||= User.new # guest user (not logged in)

    #If you can approve something, you can also reject it
    alias_action :reject, :to => :approve

    if user then

      #All users can manage themselves.
      can :manage, User, :id => user.id
      cannot :assign_roles, User
      cannot :read, User

      ######################
      # MEMBER PERMISSIONS #
      ######################
      if user.has_role? :member
        can :access, :backend

        can :read, :all
        can :sign_up_for, Admin::StaffingJob

        ##
        # Note - due the complex
        ###
        cannot :read, Admin::Proposals::Proposal
        can :read, Admin::Proposals::Proposal do |proposal|
          (proposal.users.include? user) || (proposal.approved) || (proposal.call.archived)
        end

        can :create, Admin::Proposals::Proposal
        can :edit, Admin::Proposals::Proposal do |proposal|
          (proposal.users.include? user) && (proposal.call.deadline > Time.now) && (proposal.call.open)
        end

        cannot :read, Admin::EditableBlock
        cannot :read, User
        cannot :read, :jobs
        cannot :read, Admin::Proposals::CallQuestionTemplate
      end

      #########################
      # COMMITTEE PERMISSIONS #
      #########################
      if user.has_role? :committee
        can :manage, Admin::Staffing
        can :manage, Admin::Proposals::Call
        can :make_public, Show
      end

      #####################
      # ADMIN PERMISSIONS #
      ##############################################
      # (Leave at the bottom to ensure precedence) #
      ##############################################
      if user.has_role? :admin
        can :manage, :all
      end

    else

      can :read, News, :show_public => true

    end
    #
    # The first argument to `can` is the action you are giving the user permission to do.
    # If you pass :manage it will apply to every action. Other common actions here are
    # :read, :create, :update and :destroy.
    #
    # The second argument is the resource the user can perform the action on. If you pass
    # :all it will apply to every resource. Otherwise pass a Ruby class of the resource.
    #
    # The third argument is an optional hash of conditions to further filter the objects.
    # For example, here the user can only update published articles.
    #
    #   can :update, Article, :published => true
    #
    # See the wiki for details: https://github.com/ryanb/cancan/wiki/Defining-Abilities
  end
end
