class RegistrationsController < Devise::RegistrationsController
  before_filter :validate_card_number, only: [:create, :reactivate]

  def validate_card_number
    @membership_card = MembershipCard.find_by_card_number params[:user][:card_number]

    if @membership_card.nil?
      flash[:alert] = 'Card not found'

      redirect_to :new_user_registration
      return
    end

    if not @membership_card.user.nil?
      flash[:alert] = 'Card already registered'

      redirect_to :new_user_registration
      return
    end
  end

  def create
    params[:user].delete :card_number

    super

    user = resource

    user.membership_card = @membership_card
    user.add_role :member

    resource.save!
  end

  def reactivation
    @title = "Membership Renewal"
  end

  def reactivate
    current_user.add_role :member

    if current_user.membership_card.nil?
      current_user.membership_card = @membership_card
    else
      @membership_card.delete
    end

    current_user.save!

    flash[:notice] = "Membership Reactivated. Thank you."

    redirect_to admin_path
  end
end