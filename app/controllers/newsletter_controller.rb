class NewsletterController < ApplicationController
  def subscribe
    subscription = NewsletterSubscriber.new
    subscription.email = params[:email]
    subscription.save

    flash[:success] = "Added #{params[:email]} to the mailing list. Thank you."
    return redirect_to :back
  end
end
