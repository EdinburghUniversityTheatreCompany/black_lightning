# See http://prawn.majesticseacreature.com/manual.pdf for pdf generation.
require "prawn/measurement_extensions"

class MembershipCardPDF < Prawn::Document
  def self.create(*args)
    pdf = new(*args)
    yield pdf
    pdf.tidy_up
  end

  def initialize(card)
    width  = 85.mm
    height = 55.mm

    super(
          page_size: [width, height],
          margin:    0
        )

    font  Rails.root.join("app", "assets", "fonts", "gothic.ttf")

    # Background Image
    image Rails.root.join("app", "assets", "images","card_background.jpg"), at: [0, height], fit: [width, height]

    # QR Code
    @qr_file = Tempfile.new("qr_#{card.card_number}")
    qr = RQRCode::QRCode.new(card.card_number, size: 2, level: :h )

    @qr_file.binmode
    @qr_file.write RQRCode::Renderers::PNG.render(qr)
    @qr_file.close

    image @qr_file.path, at: [5, 5 + 50], fit: [50, 50]
    # End QR Code

    bounding_box([5.1.mm, height - 14.mm], width: 31.3.mm, height: 33.7.mm) do
      font_size 7.5

      # EUTC
      font Rails.root.join("app", "assets", "fonts", "gothicb.ttf") do
        text "EDINBURGH UNIVERSITY", align: :center
        text "THEATRE COMPANY", align: :center
      end

      move_down 3.mm

      # Member
      text "MEMBER", align: :center

      move_down 3.mm

      # Name
      font Rails.root.join("app", "assets", "fonts", "gothicb.ttf") do
        text card.user.name, align: :center
      end
    end

    # Card Number
    text_box card.card_number, at: [width - 67, 11], size: 8
  end

  def tidy_up
    @qr_file.unlink
  end
end