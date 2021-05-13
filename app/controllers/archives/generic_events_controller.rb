# For the few things that are shared between the controllers of the events.

class Archives::GenericEventsController < ArchivesController
  include GenericController

  def index
    @events = load_index_resources
    super
  end

  private

  def order_args
    # Dealt with by default scope.
    nil
  end

  def index_filename
    'archives/generic_event_index'
  end

  def includes_args
    [image_attachment: :blob]
  end

  def items_per_page
    15
  end
end
