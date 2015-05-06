##
# Controller for NewsletterSubscriber. More details can be found there.
#
# Currently only handles the POST subscribe method for adding a new address to the list.
##

class NewsletterController < ApplicationController
  ##
  # POST /newsletter/subscribe
  ##
  def subscribe
    subscription = NewsletterSubscriber.new
    subscription.email = params[:email]

    if subscription.save
      flash[:success] = "Added #{params[:email]} to the mailing list. Thank you."
      return redirect_to :back
    else
      flash[:alert] = "Error subscribing to mailing list: #{subscription.errors.full_messages.join(', ')}"
      return redirect_to :back
    end
  end
end
