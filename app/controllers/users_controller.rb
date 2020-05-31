##
# Public controller for User. More details can be found there.
##
class UsersController < ApplicationController
  load_resource
  ##
  # GET /users/1
  #
  # GET /users/1.json
  ##
  def show
    authorize! :view_public_profile, @user

    @title = @user.name(current_user)

    @team_memberships = @user.team_memberships(true)

    respond_to do |format|
      format.html # show.html.erb
    end
  end
end
