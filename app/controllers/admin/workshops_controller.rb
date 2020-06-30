class Admin::WorkshopsController < AdminController
  include GenericController

  load_and_authorize_resource find_by: :slug

  # GET /admin/shows
  # GET /admin/shows.json
  def index
    @title = 'Workshops'

    @editable_block_name = 'Workshops (Members Face)'
    @url = :admin_workshops

    @q = @workshops.ransack(params[:q])
    @events = @q.result(distinct: true)
                .accessible_by(current_ability)
                .paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html { render 'admin/events/index' }
      format.json { render json: @events }
    end
  end

  private

  def order_args
    # Dealt with by default scope.
    nil
  end

  def permitted_params
    [
      :description, :name, :slug, :tagline, :author, :venue, :venue_id, :season,
      :season_id, :xts_id, :is_public, :image, :start_date, :end_date, :price,
      :spark_seat_slug, :proposal, :proposal_id,
      pictures_attributes: [:id, :_destroy, :description, :image],
      team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal]
    ]
  end
end
