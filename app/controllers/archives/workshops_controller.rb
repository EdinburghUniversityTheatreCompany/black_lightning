class Archives::WorkshopsController < Archives::GenericEventsController
  def index
    @title = 'Workshops and Events'

    @url = :archives_workshops_index

    super
  end
end
