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

    # Note this uses the ARRAY method "select" to filter results. (Since
    # teamwork is a polymorphic association, you can't just join the
    # events table and filter that).
    @shows = @user.team_membership.where({ teamwork_type: "Event" }).select { |e| (e.teamwork.is_a? Show) && (e.teamwork.is_public) }

    @shows.sort! { |a,b| a.teamwork.start_date <=> b.teamwork.start_date }

    respond_to do |format|
      format.html # show.html.erb
    end
  end

  # A json function to check if the given membership number or name
  # belongs to a current member.
  def check_membership
    search = params[:search]

    # Try a membership card
    card = MembershipCard.find_by_card_number(search)

    if not card.nil?
      if card.user.nil?
        render :json, { response: "Card Not Activated" }, status: :expectation_failed
        return
      else
        user = card.user
      end
    end

    # Else, search for a user
    q = "%#{search}%"
    user ||= User.where("CONCAT(first_name, ' ', last_name) like ?", q).first

    case
      when user.nil?
        render json: { response: "Member not found" }, status: :not_found
        return
      when user.has_role?(:member)
        render json: { response: user.name + " is a current member", image: user.avatar.url }
        return
      else
        render json: { response: user.name + " is not a current member" }, status: :payment_required
        return
    end
  end
end
