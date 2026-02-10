class Admin::EventsController < Admin::GenericEventsController
  include AcademicYearHelper

  # GET admin/shows/debt_overview
  def debt_overview
    authorize! :debt_overview, Event

    academic_year_start = start_of_year
    @shows = Event.where("end_date >= ?", academic_year_start)
                  .includes(:event_tags, :venue)
                  .order(start_date: :asc)
  end
end
