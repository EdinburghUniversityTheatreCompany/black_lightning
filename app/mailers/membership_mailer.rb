# This mailer is currently completely unused.
# :nocov:
class MembershipMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def new_member(user)
    @user = user
    @card = user.membership_card

    qr = RQRCode::QRCode.new(@card.card_number, size: 2, level: :h)
    attachments.inline['qr.png'] = RQRCode::Renderers::PNG.render(qr)

    mail(to: @user.email, subject: 'Welcome to Bedlam')
  end

  def renew_membership(user)
    @user = user
    @card = user.membership_card

    qr = RQRCode::QRCode.new(@card.card_number, size: 2, level: :h)
    attachments.inline['qr.png'] = RQRCode::Renderers::PNG.render(qr)

    mail(to: @user.email, subject: 'Bedlam Membership')
  end
end
# :nocov:
