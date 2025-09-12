# For the few things that are shared between the controllers of the events.

class PublicGenericEventsController < GenericEventsController
  def index
    @show_search_form = false

    super
  end

  def base_index_database_query
    super.current.reorder("start_date asc")
  end
end
