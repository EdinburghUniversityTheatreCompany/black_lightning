class Archives::WorkshopsController < Archives::GenericEventsController
  def index
    @title = "Workshops Archive"

    super
  end

  private

  def index_description
    "Workshops the EUTC has run at Bedlam Theatre, from acting and directing to lighting, sound and stage management."
  end
end
