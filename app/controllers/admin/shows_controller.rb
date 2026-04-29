class Admin::ShowsController < Admin::GenericEventsController
  skip_authorize_resource only: %i[convert_to_season convert_to_workshop debt_overview]

  # New is handled by the Generic Controller.
  # Create is handled by the Generic Controller.
  # Edit is handled by the Generic Controller.
  # Destroy is handled by Generic Controller.


  # POST admin/shows/1/convert_to_season
  def convert_to_season
    authorize! :convert, @show
    authorize! :create, Season

    season = convert_to(Season)

    if season.present?
      redirect_to admin_season_path(season)
    else
      redirect_to admin_show_path(@show)
    end
  end

  # POST admin/shows/1/convert_to_workshop
  def convert_to_workshop
    authorize! :convert, @show
    authorize! :create, Workshop

    workshop = convert_to(Workshop)

    if workshop.present?
      redirect_to admin_workshop_path(workshop)
    else
      redirect_to admin_show_path(@show)
    end
  end

  private

  # The show is never actually destroyed. The event just changes type.
  def convert_to(target_klass)
    authorize!(:create, target_klass)
    authorize!(:destroy, @show)

    # Preventing data duplication. Shows will not be destroyed if these are present, but the converted event will be created before that is checked.
    # To prevent that, we do this check.
    unless @show.can_convert?
      helpers.append_to_flash(:error, "There are still attached feedbacks left. You cannot convert a show with one of these attached to prevent data loss.")
      return false
    end

    event = @show.becomes!(target_klass)

    if event.save
      helpers.append_to_flash(:success, "Converted the Show \"#{@show.name}\" into the #{helpers.get_object_name(event, include_class_name: true)}.")

      event
    else
      additional_message = "There already exists a #{target_klass.name.humanize} with the slug \"#{@show.slug}\"" if target_klass.find_by(slug: @show.slug)
      helpers.append_to_flash(:error, "Could not create #{helpers.get_object_name(event, include_class_name: true)} from the Show \"#{@show.name}\". #{additional_message}")

      false
    end
  end
end
