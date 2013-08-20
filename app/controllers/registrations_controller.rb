class RegistrationsController < Devise::RegistrationsController
  def create
    membership_card = MembershipCard.find_by_card_number params[:user][:card_number]

    if membership_card.nil?
      flash[:alert] = 'Card not found'

      redirect_to :new_user_registration
      return
    end

    params[:user].delete :card_number

    super

    user = resource

    user.membership_card = membership_card
    user.add_role :member

    resource.save!
  end
end