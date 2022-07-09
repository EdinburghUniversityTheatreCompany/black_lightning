##
# Public controller for Show. More details can be found there.
#
# Uses paginate for pagination.
##
class ShowsController < GenericEventsController
  def test_report_500
    exception = ArgumentError.new('This is a test error.')

    report_500(exception)
  end

  private

  def load_index_resources
    return super.current
  end
end
