module Admin
  module Reimbursements
    ##
    # On the base portal permission, not finance: owners and producers read
    # these words on their own screens.
    class GlossaryController < BaseController
      def show
        @title = "What the words mean"
        @sections = ::Reimbursements::Glossary::SECTIONS
      end
    end
  end
end
