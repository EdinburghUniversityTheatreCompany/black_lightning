# For the few things that are shared between the controllers of the events.

class Archives::GenericEventsController < GenericEventsController
  skip_authorization_check

  def index
    @show_search_form = true

    super
  end
end
