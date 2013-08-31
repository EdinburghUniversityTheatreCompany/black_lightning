class Admin::MembershipCardsController < AdminController

  load_and_authorize_resource :find_by => :card_number

  ##
  # GET /admin/membership_cards
  ##
  def index
    @title = "Membership Cards"
    @cards = MembershipCard.paginate(:page => params[:page], :per_page => 15).all
  end

  ##
  # GET /admin/membership_cards/1
  ##
  def show
    @card = MembershipCard.find_by_card_number(params[:id])
    @title = "Membership Card #{@card.card_number}"
  end

  ##
  # POST /admin/membership_card
  ##
  def create
    @card = MembershipCard.create!

    flash[:notice] = 'Membership Card successfully created.'

    redirect_to admin_membership_card_path(@card)
  end

  ##
  # DELETE /admin/news/1
  ##
  def destroy
    @card = MembershipCard.find_by_card_number(params[:id])
    @card.destroy

    redirect_to admin_membership_cards_path
  end

  def generate_card
    @card = MembershipCard.find_by_card_number!(params[:membership_card_id])

    if @card.user.nil?
      flash[:alert] = "Card Not Activated"
      redirect_to admin_membership_card_path(@card)
      return
    end

    MembershipCardPDF.create(@card) do |pdf|
      send_data pdf.render, :filename => "card_#{@card.card_number}.pdf", :type => "application/pdf", :disposition => "inline"
    end

  end

end
