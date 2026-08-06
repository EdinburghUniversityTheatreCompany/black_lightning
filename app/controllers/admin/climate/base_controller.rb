module Admin
  module Climate
    ##
    # The crypt climate monitor, part of the members' backend. Viewing needs the
    # grid permission "View the climate monitor" (`:read, :climate`) on top of
    # backend access; configuring sensors needs `:manage, :climate`.
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
