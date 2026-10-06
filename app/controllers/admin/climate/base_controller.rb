module Admin
  module Climate
    ##
    # Base for the crypt climate monitor: `:read, :climate` to view, `:manage,
    # :climate` to configure sensors.
    class BaseController < AdminController
      before_action :authorize_climate_read!

      private

      def authorize_climate_read!
        authorize! :read, :climate
      end

      def authorize_climate_manage!
        authorize! :manage, :climate
      end
    end
  end
end
