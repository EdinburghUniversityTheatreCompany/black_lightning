# frozen_string_literal: true

module Pretix
  ##
  # Fires a membership sync when someone authorises the PRETIX shop through
  # Doorkeeper — and only then.
  #
  # Signing in to the shop is the only moment we learn a member has a pretix
  # customer account at all: pretix creates one on first login and offers no
  # webhook to say so. But Doorkeeper's after_successful_authorization fires for
  # every OAuth client the society runs, and a sync for someone signing in to an
  # unrelated app is two pointless pretix API reads.
  #
  # Lives here rather than inline in the initializer so it can be tested and so
  # the initializer stays a configuration file.
  module LoginSync
    def self.call(controller)
      return unless Settings.configured?

      user = controller.send(:current_user)
      return if user.blank?
      return unless pretix_client?(controller.request.params[:client_id])

      # Deferred: on a FIRST login pretix has not finished the token exchange
      # when this fires, so the customer does not exist yet and an immediate
      # sync would find nothing to attach a membership to.
      SyncMembershipJob.set(wait: SyncMembershipJob::FIRST_LOGIN_DELAY).perform_later(user.id)
    end

    # Identified by where the client sends people back to, rather than by a uid
    # recorded in config: the uid is generated per environment, so a stored one
    # would be wrong everywhere it was not generated.
    def self.pretix_client?(client_id)
      return false if client_id.blank?

      application = Doorkeeper::Application.find_by(uid: client_id)
      return false if application.blank?

      application.redirect_uri.to_s.include?(Settings::SHOP_HOST)
    end
  end
end
