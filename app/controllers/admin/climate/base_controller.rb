module Admin
  module Climate
    ##
    # The crypt climate monitor, part of the members' backend. Viewing needs the
    # grid permission "View the climate monitor" (`:read, :climate`) on top of
    # backend access; configuring sensors needs `:manage, :climate`.
    class BaseController < AdminController
      before_action :authorize_climate_read!

      # Injection seam for functional tests (this suite has no mocking library).
      #
      # Written on THIS class and nowhere else. class_attribute's writer defines
      # a singleton reader on whatever receives it, so writing to a SUBCLASS
      # would shadow this default permanently for the rest of the process — a
      # later assignment here would then be invisible to that subclass and the
      # real client would run instead. A test must restore it in teardown.
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
