class Admin::MassMailsController < AdminController
  include GenericController

  load_and_authorize_resource

  # Index is handled by the Generic Controller.

  # Show is handled by the Generic Controller.

  ##
  # GET /admin/mass_mails/new
  #
  # GET /admin/mass_mails/new.json
  ##
  def new
    @mass_mail.draft = true

    super
  end

  ##
  # GET /admin/mass_mails/1/edit
  ##
  def edit
    if @mass_mail.draft
      super
    else
      flash[:error] = 'Mail cannot be edited once it has been sent'

      respond_to do |format|
        format.html { redirect_to admin_mass_mails_url }
        format.json { head :no_content }
      end
    end
  end

  # Create is handled by the Generic Controller.

  ##
  # PUT /admin/mass_mails/1
  #
  # PUT /admin/mass_mails/1.json
  ##
  def update
    send = params.delete(:send)

    if @mass_mail.update(update_params)
      if send
        send_mail @mass_mail
      else
        flash[:success] = 'Mass mail was successfully updated.'
        respond_to do |format|
          format.html { redirect_to admin_mass_mail_url(@mass_mail) }
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
    if @mass_mail.draft
      super
    else
      flash[:error] = 'This mass mail has been sent and can not be deleted.'

      respond_to do |format|
        format.html { redirect_back fallback_location: admin_mass_mails_url }
        format.json { render json: { error: flash[:error] } }
      end
    end
  end

  private

  def permitted_params
    [:body, :draft, :send_date, :subject]
  end

  def order_args
    :send_date
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
