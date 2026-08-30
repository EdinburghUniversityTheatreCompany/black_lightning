##
# Public controller for Workshop. More details can be found there.
#
# Uses paginate for pagination.
##
class WorkshopsController < PublicGenericEventsController
  private

  def index_description
    "Free workshops at Bedlam Theatre: acting, directing, lighting, sound and stage management, open to students of any experience."
  end
end
