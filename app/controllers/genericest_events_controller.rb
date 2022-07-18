# Should be included as a mix-in in any events controllers you want to use it in. Use:
# includes GenericController
module GenericestEventsController
  include GenericController

  def index
    @events = load_index_resources

    super
  end

  private

  def base_index_database_query
    return super.on_date(Date.current) if params[:commit].upcase == 'ON THIS DAY'

    return super
  end

  def order_args
   ['end_date DESC']
  end
end
