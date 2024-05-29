# This mailer is currently completely unused.
# :nocov:
class MembershipMailer < ApplicationMailer
  def new_member(user)
    @user = user
    @card = user.membership_card
    @subject = 'Welcome to Bedlam'

    qr = RQRCode::QRCode.new(@card.card_number, size: 2, level: :h)
    attachments.inline['qr.png'] = RQRCode::Renderers::PNG.render(qr)

    mail(to: email_address_with_name(@user.email, @user.full_name), subject: @subject)
  end

  def renew_membership(user)
    @user = user
    @card = user.membership_card
    @subject = 'Bedlam Membership'

    qr = RQRCode::QRCode.new(@card.card_number, size: 2, level: :h)
    attachments.inline['qr.png'] = RQRCode::Renderers::PNG.render(qr)

    mail(to: email_address_with_name(@user.email, @user.full_name), subject: @subject)
  end
end
# :nocov:
