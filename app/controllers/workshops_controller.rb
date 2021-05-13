##
# Public controller for Workshop. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class WorkshopsController < GenericEventsController

  private

  def load_index_resources
    return super.current
  end
end
