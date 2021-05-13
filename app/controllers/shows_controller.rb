##
# Public controller for Show. More details can be found there.
#
# Uses Will_Paginate for pagination.
##
class ShowsController < GenericEventsController
  
  private

  def load_index_resources
    return super.current
  end
end
