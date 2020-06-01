class Admin::ShowsController < AdminController
  load_and_authorize_resource find_by: :slug
  skip_load_resource only: %i[index]
  # Those are checked for permission to create debts instead.
  skip_authorize_resource only: %i[create_maintenance_debts create_staffing_debts]

  # GET /admin/shows
  # GET /admin/shows.json
  def index
    @title = 'Shows'

    @editable_block_name = 'Shows (Members Face)'
    @url = :admin_shows

    @q = Show.ransack(params[:q])
    @events = @q.result(distinct: true)
                .accessible_by(current_ability)
                .paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html { render 'admin/events/index' }
      format.json { render json: @events }
    end
  end

  def show
    @questionnaires = @show.questionnaires.accessible_by(current_ability)
    @title = @show.name

    existing_staffing_debts = Admin::StaffingDebt.where(show: @show)
    if existing_staffing_debts.any?
      amount_of_debts = existing_staffing_debts.where(user: existing_staffing_debts.first.user).count

      @staffing_confirm_data = {
        confirm: 'Creating Staffing Obligation',
        detail: "This show already has #{helpers.pluralize(amount_of_debts, 'Staffing obligation')} set for
         #{l existing_staffing_debts.first.due_by, format: :longy}. Are you sure you want to add more?"
      }
    else
      @staffing_confirm_data = {}
    end
  end

  def new
    # Title set by the view.
  end

  def create
    respond_to do |format|
      if @show.save
        format.html { redirect_to admin_show_url(@show), notice: 'Show was successfully created.' }
      else
        format.html { render 'new', status: :unprocessable_entity }
      end
    end
  end

  def edit
    # Title set by the view.
  end

  def update
    previous_user_ids = @show.users.ids

    if @show.update(show_params)

      flash[:notice] = 'The show was successfully updated.'

      # Used to check any new users being added are not in debt.
      if params[:show][:team_members_attributes]
        parameter_user_ids = params[:show][:team_members_attributes].values.collect { |e| e[:user_id].to_i }.uniq
        new_user_ids = parameter_user_ids - previous_user_ids

        new_users = User.where(id: new_user_ids)
        new_debtors = new_users.select(&:in_debt)

        if new_debtors.any?
          new_debtors_string = new_debtors.collect(&:name).to_sentence
          flash[:notice] = "The show was successfully updated, but #{new_debtors_string} #{'is'.pluralize(new_debtors.count)} in debt."

          ShowMailer.warn_committee_about_debtors_added_to_show(@show, new_debtors_string, @current_user).deliver_later
        end
      end

      respond_to do |format|
        format.html { redirect_to admin_show_url(@show) }
      end
    else
      respond_to do |format|
        format.html { render 'edit', status: :unprocessable_entity }
      end
    end
  end

  def destroy
    helpers.destroy_with_flash_message(@show)

    respond_to do |format|
      format.html { redirect_to admin_shows_url }
      format.json { head :no_content }
    end
  end

  # POST admin/shows/1/create_maintenance_debts
  def create_maintenance_debts
    authorize! :create, Admin::MaintenanceDebt

    if @show.maintenance_debt_start.present?
      @show.create_maintenance_debts
      flash[:notice] = 'Maintenance obligations created.'
    else
      flash[:notice] = 'Could not create Maintenance obligations because the start date has not been set yet.'
    end

    redirect_to admin_show_path(@show)
  end

  # POST admin/shows/1/create_staffing_debts
  def create_staffing_debts
    authorize! :create, Admin::StaffingDebt

    if params[:number_of_slots].nil?
      flash[:notice] = 'You have to specify the amount of Staffing slots you want to create.'
    elsif @show.staffing_debt_start.present?
      amount = params[:number_of_slots].first.to_i
      @show.create_staffing_debts(amount)
      flash[:notice] = "#{helpers.pluralize(amount, 'Staffing obligation slot')} created for every team member."
    else
      flash[:notice] = 'Could not create Staffing obligations because the start date has not been set yet.'
    end

    redirect_to admin_show_path(@show)
  end

  # It is only there for legacy purposes.
  # :nocov:
  def query_xts
    username = Rails.application.config.xts[:username]
    password = Rails.application.config.xts[:password]

    uniq = Time.now.to_i

    # ?uniq=1355693791607&includedatetimes=true&agents=boxoffice:9n2nf92kt04&agents=boxoffice:9n2nf92kt04|craig:insecure

    xts_api_uri = "https://internal.bedlamtheatre.co.uk:8443/xts/v2/tickets/getshows?uniq=#{uniq}&includedatetimes=true&agents=#{username}:#{password}"

    uri = URI.parse(xts_api_uri)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    xml_data = response.body

    doc = Nokogiri::XML(xml_data)

    # Convert the xml into an array of hashes.
    shows = []

    doc.xpath('shows/showsummary').each do |element|
      show = {}
      element.children.each do |child|
        show[child.name] = child.text
      end
      shows << show
    end

    shows = shows.select { |show| show['name'] == params[:name] } if params[:name]

    render json: shows.to_json
  end

  def xts_report
    xts_api_uri = "https://internal.bedlamtheatre.co.uk:8443/xts/v2/reports/show?showid=#{show.xts_id}"

    uri = URI.parse(xts_api_uri)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)
    data = response.body
    send_data(data, filename: "#{show.name} - Sales Report.pdf", type: 'application/pdf')
  end
  #:nocov:

  private

  def show_params
    params.require(:show).permit(:maintenance_debt_start, :staffing_debt_start, :description, :name, :slug, :tagline,
                                 :author, :venue, :venue_id, :season, :season_id, :xts_id, :is_public, :image,
                                 :start_date, :end_date, :price, :spark_seat_slug,
                                 reviews_attributes: [:id, :_destroy, :body, :rating, :review_date, :organisation, :reviewer, :show_id],
                                 pictures_attributes: [:id, :_destroy, :description, :image],
                                 team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal, :proposal_id])
  end
end
