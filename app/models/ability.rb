##
# Defines the abilities for each user. See CanCan documentation for more details.
#
# It reads the permissions model in the database to find if a user can do something.
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

      can do |action, subject_class, subject|
        allow = false

        user.roles.each do |role|
          Rails.logger.debug action
          Rails.logger.debug subject_class
          Rails.logger.debug [aliases_for_action(action), :manage].flatten

          allow = true if role.permissions.find_all_by_action([aliases_for_action(action), :manage].flatten).any?

          Rails.logger.debug allow
        end

        next allow
      end

      cannot :read, Admin::Proposals::Proposal
      can :read, Admin::Proposals::Proposal do |proposal|
        (proposal.users.include? user) || (proposal.approved) || (proposal.call.archived)
      end

      cannot :read, Admin::Questionnaires::Questionnaire
      can :read, Admin::Questionnaires::Questionnaire do |questionnaire|
        (questionnaire.users.include? user)
      end

      can :answer, Admin::Questionnaires::Questionnaire do |questionnaire|
        (questionnaire.users.include? user)
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
