class Admin::ShowsController < AdminController
  load_and_authorize_resource find_by: :slug

  def index
    @title = 'Shows'

    @q = Show.unscoped.search(params[:q])
    @shows = @q.result(distinct: true)
    @shows = @shows.order('start_date DESC')
    @shows = @shows.paginate(page: params[:page], per_page: 15).all
  end

  def show
    @show = Show.find_by_slug(params[:id])
    @title = @show.name
  end

  def new
    @show = Show.new
    @users = User.all
    @title = 'New Show'
  end

  def create
    @show = Show.new(params[:show])
    @users = User.all

    respond_to do |format|
      if @show.save
        format.html { redirect_to admin_show_url(@show), notice: 'Show was successfully created.' }
      else
        format.html { render 'new' }
      end
    end
  end

  def edit
    @show = Show.find_by_slug(params[:id])
    @users = User.all
    @title = "Editing #{@show.name}"
  end

  def update
    @show = Show.find_by_slug(params[:id])
    @users = User.all

    respond_to do |format|
      if @show.update_attributes(params[:show])
        format.html { redirect_to admin_show_url(@show), notice: 'Show was successfully updated.' }
      else
        format.html { render 'edit' }
      end
    end
  end

  def destroy
    @show = Show.find_by_slug(params[:id])
    @show.destroy

    respond_to do |format|
      format.html { redirect_to admin_shows_url }
      format.json { head :no_content }
    end
  end

  def add_questionnaire
    @show = Show.find_by_slug(params[:id])
    @show.create_questionnaire(params[:questionnaire_name])

    respond_to do |format|
      format.html { redirect_to admin_show_url(@show), notice: 'Questionnaire will be created.' }
      format.html { render :no_content }
    end
  end

  def create_mdebts
    authorize! :create, Admin::MaintenanceDebt
    @show = Show.find_by_slug(params[:id])
    @show.create_mdebts

    respond_to do |format|
      format.html { redirect_to admin_show_url(@show), notice: 'Obligations created.' }
      format.html { render :no_content }
    end
  end

  def create_sdebts
    authorize!(:create , Admin::StaffingDebt)
    @show = Show.find_by_slug(params[:id])
    @show.create_sdebts(params[:number_of_slots_due][0].to_i)

    respond_to do |format|
      format.html { redirect_to admin_show_url(@show), notice: 'Obligations created.' }
      format.html { render :no_content }
    end
  end

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

    if params[:name]
      shows = shows.reject { |show| show['name'] != params[:name] }
    end

    render json: shows.to_json
  end

  def xts_report
    show = Show.find_by_slug(params[:id])
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
end
