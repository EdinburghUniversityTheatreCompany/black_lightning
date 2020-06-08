class Admin::MembershipCardsController < AdminController
  load_and_authorize_resource find_by: :card_number

  ##
  # GET /admin/membership_cards
  ##
  def index
    @title = 'Membership Cards'
    @cards = @membership_cards.paginate(page: params[:page], per_page: 15)
  end

  ##
  # GET /admin/membership_cards/1
  ##
  def show
    @title = "Membership Card #{@card.card_number}"
  end

  ##
  # POST /admin/membership_card
  ##
  def create
    flash[:notice] = 'Membership Card successfully created.'

    redirect_to admin_membership_card_path(@card)
  end

  ##
  # DELETE /admin/news/1
  ##
  def destroy
    helpers.destroy_with_flash_message(@card.destroy)

    redirect_to admin_membership_cards_path
  end

  def generate_card
    if @card.user.nil?
      flash[:error] = 'Card Not Activated'
      redirect_to admin_membership_card_path(@card)
      return
    end

    MembershipCardPdf.create(@card) do |pdf|
      send_data pdf.render, filename: "card_#{@card.card_number}.pdf", type: 'application/pdf', disposition: 'inline'
    end
  end
end
