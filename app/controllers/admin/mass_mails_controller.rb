class Admin::MassMailsController < AdminController
  load_and_authorize_resource

  ##
  # GET /admin/mass_mails
  #
  # GET /admin/mass_mails.json
  ##
  def index
    @title = 'Mass Mails'

    @mass_mails = @mass_mails.order(:send_date).paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @mass_mails }
    end
  end

  ##
  # GET /admin/mass_mails/1
  #
  # GET /admin/mass_mails/1.json
  ##
  def show
    @title = @mass_mail.subject

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @mass_mail }
    end
  end

  ##
  # GET /admin/mass_mails/new
  #
  # GET /admin/mass_mails/new.json
  ##
  def new
    @title = 'New Mass Mail'

    @mass_mail.draft = true

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @mass_mail }
    end
  end

  ##
  # GET /admin/mass_mails/1/edit
  ##
  def edit
    @title = "Edit #{@mass_mail.subject}"

    if @mass_mail.draft == false
      respond_to do |format|
        format.html { redirect_to admin_mass_mails_url, notice: 'Mail cannot be edited once it has been sent' }
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html
        format.json { render json: @mass_mail }
      end
    end
  end

  ##
  # POST /admin/mass_mails
  #
  # POST /admin/mass_mails.json
  ##
  def create
    send = params.delete(:send)

    if @mass_mail.save
      if send
        send_mail @mass_mail
      else
        respond_to do |format|
          format.html { redirect_to admin_mass_mail_url(@mass_mail), notice: 'Mass mail was successfully created.' }
          format.json { render json: @mass_mail, status: :created, location: @mass_mail }
        end
      end
    else
      respond_to do |format|
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: admin_mass_mails_url.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/mass_mails/1
  #
  # PUT /admin/mass_mails/1.json
  ##
  def update
    send = params.delete(:send)

    if @mass_mail.update(mass_mail_params)
      if send
        send_mail @mass_mail
      else
        respond_to do |format|
          format.html { redirect_to admin_mass_mail_url(@mass_mail), notice: 'Mass mail was successfully updated.' }
          format.json { head :no_content }
        end
      end
    else
      respond_to do |format|
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @mass_mail.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/mass_mails/1
  #
  # DELETE /admin/mass_mails/1.json
  ##
  def destroy
    respond_to do |format|
      if @mass_mail.draft
        helpers.destroy_with_flash_message(@mass_mail)

        format.html { redirect_to admin_mass_mails_url }
        format.json { head :no_content }
      else
        format.html { redirect_back fallback_location: admin_mass_mails_url, notice: 'This mass mail has been sent and can not be deleted.' }
        format.json { render json: { error: 'This mass mail has been sent and can not be deleted.' } }
      end
    end
  end

  private

  def mass_mail_params
    params.require(:mass_mail).permit(:body, :draft, :send_date, :subject)
  end

  def send_mail(mail)
    begin
      mail.update! sender: current_user, recipients: User.with_role(:member)
      mail.prepare_send!

      @error_message = nil
    rescue Exceptions::MassMail::MassMailError => e
      @error_message = e.message
    rescue ActiveRecord::RecordInvalid
      @error_message = mail.errors
    end

    if @error_message.nil?
      respond_to do |format|
        format.html { redirect_to admin_mass_mail_url(mail), notice: 'Mass mail will be sent.' }
        format.json { render json: mail, status: :created, location: mail }
      end
    else
      respond_to do |format|
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: { error: @error_message }, status: :unprocessable_entity }
      end
    end
  end
end
