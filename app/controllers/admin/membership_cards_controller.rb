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
            page_size:  [width, height],
            margin: 0
          )
    pdf.font Rails.root.join("app", "assets", "fonts", "gothic.ttf")

    pdf.image Rails.root.join("app", "assets", "images","card_background.jpg"), at: [0, height], fit: [width, height]

    # QR Code
    qr_file = Tempfile.new("qr_#{@card.card_number}")
    qr = RQRCode::QRCode.new(@card.card_number, size: 2, level: :h )

    qr_file.binmode
    qr_file.write RQRCode::Renderers::PNG.render(qr)
    qr_file.close

    pdf.image qr_file.path, at: [5, 5 + 50], fit: [50, 50]
    # End QR Code

    pdf.bounding_box([5.1.mm, height - 14.mm], width: 31.3.mm, height: 33.7.mm) do
      pdf.font_size 7.5

      # EUTC
      pdf.font Rails.root.join("app", "assets", "fonts", "gothicb.ttf") do
        pdf.text "EDINBURGH UNIVERSITY", align: :center
        pdf.text "THEATRE COMPANY", align: :center
      end

      pdf.move_down 3.mm

      # Member
      pdf.text "MEMBER", align: :center

      pdf.move_down 3.mm

      # Name
      pdf.font Rails.root.join("app", "assets", "fonts", "gothicb.ttf") do
        pdf.text @card.user.name, align: :center
      end
    end

    pdf.text_box @card.card_number, at: [width - 67, 11], size: 8

    send_data pdf.render, :filename => "card_#{@card.card_number}.pdf", :type => "application/pdf", :disposition => "inline"

    qr_file.unlink
  end

end
