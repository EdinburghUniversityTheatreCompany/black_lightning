##
# Public controller for User. More details can be found there.
##
class UsersController < ApplicationController
  include GenericController

  load_resource
  ##
  # GET /users/1
  #
  # GET /users/1.json
  ##
  def show
    authorize! :view_shows_and_bio, @user

    @title = @user.name(current_user)

    @team_memberships = @user.team_memberships(true)

    super
  end

  def consent
    authorize! :edit, @user

    @user.touch(:consented)

    redirect_to(admin_path)
  end
end
