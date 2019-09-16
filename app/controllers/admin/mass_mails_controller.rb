class Admin::MassMailsController < AdminController
  load_and_authorize_resource

  def send_mail(mail)
    mail.recipients = User.with_role :member
    mail.sender     = current_user
    mail.draft      = false
    mail.save!
    mail.send!

    respond_to do |format|
      format.html { redirect_to admin_mass_mail_url(mail), notice: 'Mass mail will be sent.' }
      format.json { render json: @mass_mail, status: :created, location: @mass_mail }
    end
  end

  ##
  # GET /admin/mass_mails
  #
  # GET /admin/mass_mails.json
  ##
  def index
    @mass_mails = MassMail.paginate(page: params[:page], per_page: 15).all
    @title = 'Mass Mails'
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @mass_mails }
    end
  end

  ##
  # GET /admin/mass_mails/new
  #
  # GET /admin/mass_mails/new.json
  ##
  def new
    @mass_mail = MassMail.new
    @mass_mail.draft = true

    @title = 'New Mass Mail'
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @mass_mail }
    end
  end

  ##
  # GET /admin/mass_mails/1/edit
  ##
  def edit
    @mass_mail = MassMail.find(params[:id])

    if @mass_mail.draft == false
      respond_to do |format|
        format.html { redirect_to admin_mass_mails_url, notice: 'Mail cannot be edited once it has been sent' }
        format.json { head :no_content }
      end
    end

    @title = "Edit #{@mass_mail.subject}"
  end

  ##
  # POST /admin/mass_mails
  #
  # POST /admin/mass_mails.json
  ##
  def create
    send = params.delete(:send)

    @mass_mail = MassMail.new(mass_mail_params)

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
        format.html { render 'new' }
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

    @mass_mail = MassMail.find(params[:id])

    respond_to do |format|
      if @mass_mail.update_attributes(mass_mail_params)
        if send
          send_mail @mass_mail
        else
          format.html { redirect_to admin_mass_mail_url(@mass_mail), notice: 'Mass mail was successfully updated.' }
          format.json { head :no_content }
        end
      else
        format.html { render 'edit' }
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
    @mass_mail = MassMail.find(params[:id])
    @mass_mail.destroy

    respond_to do |format|
      format.html { redirect_to admin_mass_mails_url }
      format.json { head :no_content }
    end
  end

  private
  def mass_mail_params
    params.require(:mass_mail).permit(:body, :draft, :send_date, :sender_id, :subject)
  end
end
