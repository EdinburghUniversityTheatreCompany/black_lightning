class Archives::WorkshopsController < Archives::GenericEventsController
  def index
    @title = "Workshops Archive"

    super
  end

  private

  def index_description
    "Workshops the EUTC has run at Bedlam Theatre over the years \u2014 the full archive, not just what is coming up."
  end
end
