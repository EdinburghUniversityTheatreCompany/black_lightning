##
# Defines the abilities for each user. See CanCan documentation for more details.
#
# It reads the Admin::Permission model in the database to find if a user can do something.
#
# PLEASE, PLEASE, make sure that
#
#   if user.has_role? :admin
#     can :manage, :all
#   end
#
# is included as the last thing in the initialize method.
# This ensures that users with the admin role will _always_ have permission to do everything.
##

class Ability
  include CanCan::Ability

  def initialize(user)

    #If you can approve something, you can also reject it
    alias_action :reject, :to => :approve

    if user then

      #All users can manage themselves.
      can :manage, User, :id => user.id
      cannot :assign_roles, User
      cannot :read, User

      can do |action, subject_class, subject|
        allow = false

        user.roles.each do |role|

          if subject_class == Symbol then
            subject_class = subject
          end

          if role.permissions.where(:action => [aliases_for_action(action), :manage].flatten, :subject_class => subject_class).any? then
            allow = true
          end
        end

        next allow
      end

      can :read, Admin::Proposals::Proposal do |proposal|
        (proposal.users.include? user) || (proposal.approved) || (proposal.call.archived)
      end

      can :create, Admin::Proposals::Proposal
      can :edit, Admin::Proposals::Proposal do |proposal|
        (proposal.users.include? user) && (proposal.call.deadline > Time.now) && (proposal.call.open)
      end

      can :read, Admin::Questionnaires::Questionnaire do |questionnaire|
        (questionnaire.users.include? user)
      end

      can :answer, Admin::Questionnaires::Questionnaire do |questionnaire|
        (questionnaire.users.include? user)
      end

      can :read, Admin::Feedback do |feedback|
        feedback.show.users.all.include? user
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
  end
end
