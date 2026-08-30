class SeasonsController < PublicGenericEventsController
  # GET /seasons/1
  def show
    @events = @season.events.reorder(:start_date).group_by { |event| l event.start_date, format: :longy }

    # A season answers on two routes -- /seasons/:slug and the short /:slug from the catch-all at
    # the bottom of routes.rb -- so the same content has two URLs. Pin both to the long form, the
    # one polymorphic_url builds and every internal link, the sitemap and the breadcrumb use.
    # Without this the self-referencing canonical endorses whichever URL was requested and the two
    # compete.
    @canonical_url = season_url(@season)

    super
  end

  private

  def index_description
    "Festivals and seasons at Bedlam Theatre, from the Bedlam Fringe to Halfbaked and the Improverts' year-round run."
  end
end
