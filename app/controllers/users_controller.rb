##
# Public controller for User. More details can be found there.
##
class UsersController < ApplicationController
  def current
    render json: current_user
  end

  ##
  # GET /users/1
  #
  # GET /users/1.json
  ##
  def show
    @user = User.where(public_profile: true).find(params[:id])
    @title = @user.name

    # Note this uses the ARRAY method "select" to filter results. (Since
    # teamwork is a polymorphic association, you can't just join the
    # events table and filter that).
    @shows = @user.team_membership.where(teamwork_type: 'Event').select { |e| (e.teamwork.is_a? Show) && (e.teamwork.is_public) }

    @shows.sort! { |a, b| a.teamwork.start_date <=> b.teamwork.start_date }

    respond_to do |format|
      format.html # show.html.erb
    end
  end
end
