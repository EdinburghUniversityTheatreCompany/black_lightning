class Archives::ShowsController < Archives::GenericEventsController
  def index
    super
    
    @title = 'Show Archive'
    @url = :archives_shows
  end
end
