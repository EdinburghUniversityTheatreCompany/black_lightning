module Admin
  module Climate
    ##
    # The crypt climate monitor, part of the members' backend. Viewing needs the
    # grid permission "View the climate monitor" (`:read, :climate`) on top of
    # backend access; configuring sensors needs `:manage, :climate`.
    class BaseController < AdminController
      before_action :authorize_climate_read!

      # Test seam, written on THIS class and nowhere else. class_attribute's
      # writer defines a singleton on whatever receives it, so a SUBCLASS
      # assignment shadows this default for the rest of the process and a later
      # assignment here becomes invisible. Tests must restore it in teardown.
      class_attribute :govee_client_builder, default: -> { ::Climate::GoveeClient.new }

      private

      def authorize_climate_read!
        authorize! :read, :climate
      end

      def authorize_climate_manage!
        authorize! :manage, :climate
      end

      def govee_client
        @govee_client ||= govee_client_builder.call
      end
    end
  end
end
