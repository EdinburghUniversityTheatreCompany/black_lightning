class SeasonsController < PublicGenericEventsController
  # GET /seasons/1
  def show
    @events = @season.events.reorder(:start_date).group_by { |event| l event.start_date, format: :longy }

    # A season answers on two routes -- /seasons/:slug and the short /:slug catch-all -- so the
    # same content has two URLs. Both pin to the long form, which polymorphic_url, the sitemap and
    # the breadcrumb already use; otherwise the self-referencing canonical endorses both.
    @canonical_url = season_url(@season)

    super
  end

  private

  def index_description
    "Festivals and seasons at Bedlam Theatre, from the Bedlam Fringe to Halfbaked and the Improverts' year-round run."
  end
end
