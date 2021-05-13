# For the few things that are shared between the controllers of the events.

class Archives::GenericEventsController < GenericEventsController
  skip_authorization_check
  layout 'archives'
end
