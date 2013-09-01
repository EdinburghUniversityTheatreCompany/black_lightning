class RegistrationsController < Devise::RegistrationsController
  def new
    @user = User.new
  end

  def create
    @membership_card = MembershipCard.find_by_card_number params[:user][:card_number]

    params[:user].delete :card_number
    @user = User.new(params[:user])

    if @membership_card.nil?
      flash[:alert] = 'Card not found'

      render 'new'
      return
    end

    if not @membership_card.user.nil?
      flash[:alert] = 'Card already registered'

      render 'new'
      return
    end

    @user.membership_card = @membership_card
    @user.add_role :member

    if user.save
      set_flash_message :notice, :signed_up
      sign_in(User, @user)

      MembershipMailer.delay.new_member(@user)

      redirect_to admin_path
    else
      render 'new'
    end
  end

  def reactivation
    @title = "Membership Renewal"
  end

  def reactivate
    @membership_card = MembershipCard.find_by_card_number params[:user][:card_number]

    if @membership_card.nil?
      flash[:alert] = 'Card not found'

      render 'registrations/reactivation'
      return
    end

    if not @membership_card.user.nil?
      flash[:alert] = 'Card already registered'

      render 'registrations/reactivation'
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

    flash[:notice] = "Membership Reactivated. Thank you."

    redirect_to admin_path
  end
end