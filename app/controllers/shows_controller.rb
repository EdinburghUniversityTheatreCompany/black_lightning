##
# Public controller for Show. More details can be found there.
#
# Uses paginate for pagination.
##
class ShowsController < PublicGenericEventsController
  private

  def index_description
    "Plays, musicals and comedy staged by Edinburgh University Theatre Company at Bedlam Theatre \u2014 what's running now and what's coming up."
  end
end
