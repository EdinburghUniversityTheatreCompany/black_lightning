##
# Public controller for User. More details can be found there.
##
class UsersController < ApplicationController

  ##
  # GET /users/1
  #
  # GET /users/1.json
  ##
  def show
    @user = User.where({:public_profile => true}).find(params[:id])
    @title = @user.name

    respond_to do |format|
      format.html # show.html.erb
    end
  end

end
