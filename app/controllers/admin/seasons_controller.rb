class Admin::SeasonsController < AdminController
  include GenericController

  load_and_authorize_resource find_by: :slug

  # GET /admin/seasons
  # GET /admin/seasons.json
  def index
    @title = 'Seasons'

    @editable_block_name = 'Seasons (Members Face)'
    @url = :admin_seasons

    @q = @seasons.ransack(params[:q])
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
      :name, :tagline, :slug, :description, :start_date, :end_date, :image,
      :venue_id, :proposal, :proposal_id, :is_public, :author, :price, event_tag_ids: [],
      pictures_attributes: [:id, :_destroy, :description, :image],
      team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal],
      event_ids: []
    ]
  end
end
