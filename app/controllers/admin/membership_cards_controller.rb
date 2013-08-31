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

  # See http://prawn.majesticseacreature.com/manual.pdf for pdf generation.
  require "prawn/measurement_extensions"
  def generate_card
    @card = MembershipCard.find_by_card_number!(params[:membership_card_id])

    width  = 85.mm
    height = 55.mm

    pdf = Prawn::Document.new(
            page_size: [width, height],
            margin: 0
          )

    pdf.text_box "Bedlam Theatre", at: [5, height - 5]

    # QR Code
    qr_file = Tempfile.new("qr_#{@card.card_number}")
    qr = RQRCode::QRCode.new(@card.card_number, size: 2, level: :h )

    qr_file.binmode
    qr_file.write RQRCode::Renderers::PNG.render(qr)
    qr_file.close

    pdf.image qr_file.path, at: [width - 80 - 5, 5 + 80], fit: [80, 80]

    if @card.user
      pdf.text_box @card.user.name, at: [5, height - 20]
    end

    pdf.text_box @card.card_number, at: [width - 67, 5 + 80 + 12], size: 8

    send_data pdf.render, :filename => "card_#{@card.card_number}.pdf", :type => "application/pdf", :disposition => "inline"

    qr_file.unlink
  end

end
