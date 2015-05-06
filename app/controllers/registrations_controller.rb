class RegistrationsController < Devise::RegistrationsController
  def new
    @user = User.new
  end

  def create
    @membership_card = MembershipCard.find_by_card_number params[:user][:card_number]

    params[:card_number] = params[:user].delete :card_number
    @user = User.new(params[:user])

    if @membership_card.nil?
      flash[:alert] = 'Card not found. It is possible that you have missed a digit, does your number start with 1?'

      respond_to do |format|
        format.html { render 'new' }
        format.json { render json: { error: 'Card not found' }, status: :unprocessable_entity }
      end
      return
    end

    unless @membership_card.user.nil?
      flash[:alert] = 'Card already registered'

      respond_to do |format|
        format.html { render 'new' }
        format.json { render json: { error: 'Card already registered' }, status: :unprocessable_entity }
      end
      return
    end

    @user.membership_card = @membership_card
    @user.add_role :member

    if @user.save
      set_flash_message :notice, :signed_up

      MembershipMailer.delay.new_member(@user)

      respond_to do |format|
        format.html do
          sign_in(User, @user)
          redirect_to admin_path
        end
        format.json { render json: { success: true } }
      end
    else
      respond_to do |format|
        format.html { render 'new' }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  before_filter only: [:reactivate, :reactivation] do
    authenticate_user!
  end

  def reactivation
    @title = 'Membership Renewal'
  end

  skip_before_filter :verify_authenticity_token, only: :reactivate
  def reactivate
    @membership_card = MembershipCard.find_by_card_number params[:user][:card_number]

    if @membership_card.nil?
      flash[:alert] = 'Card not found'

      respond_to do |format|
        format.html { render 'registrations/reactivation' }
        format.json { render json: { error: 'Card not found' } }
      end
      return
    end

    unless @membership_card.user.nil?
      flash[:alert] = 'Card already registered'

      respond_to do |format|
        format.html { render 'registrations/reactivation' }
        format.json { render json: { error: 'Card already registered' } }
      end
      return
    end

    if current_user.membership_card.nil?
      current_user.membership_card = @membership_card
    else
      @membership_card.delete
    end

    current_user.add_role :member
    current_user.save!

    MembershipMailer.delay.renew_membership(current_user)

    flash[:notice] = 'Membership Reactivated. Thank you.'

    respond_to do |format|
      format.html { redirect_to admin_path }
      format.json { render json: { success: true } }
    end
  end
end
