class Admin::DebtNotificationsController < ApplicationController
  before_action :set_admin_debt_notification, only: [:show, :edit, :update, :destroy]

  # GET /admin/debt_notifications
  def index
    @admin_debt_notifications = Admin::DebtNotification.all
  end

  # GET /admin/debt_notifications/1
  def show
  end

  # GET /admin/debt_notifications/new
  def new
    @admin_debt_notification = Admin::DebtNotification.new
  end

  # GET /admin/debt_notifications/1/edit
  def edit
  end

  # POST /admin/debt_notifications
  def create
    @admin_debt_notification = Admin::DebtNotification.new(admin_debt_notification_params)

    if @admin_debt_notification.save
      redirect_to @admin_debt_notification, notice: 'Debt notification was successfully created.'
    else
      render :new
    end
  end

  # PATCH/PUT /admin/debt_notifications/1
  def update
    if @admin_debt_notification.update(admin_debt_notification_params)
      redirect_to @admin_debt_notification, notice: 'Debt notification was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /admin/debt_notifications/1
  def destroy
    @admin_debt_notification.destroy
    redirect_to admin_debt_notifications_url, notice: 'Debt notification was successfully destroyed.'
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_admin_debt_notification
      @admin_debt_notification = Admin::DebtNotification.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def admin_debt_notification_params
      params.require(:admin_debt_notification).permit(:user_id, :sent_on)
    end
end
