module Admin
  module Reimbursements
    ##
    # The words this portal is built on.
    #
    # Gated on the base portal permission, not the finance one, and
    # deliberately: a budget OWNER reads "committed", "left" and "endorse" on
    # their own area page, and a producer reads "Submitted" on their claim and
    # has every reason to wonder why it says that when they submitted it weeks
    # ago. A glossary the people reading the words cannot open is not one.
    class GlossaryController < BaseController
      def show
        @title = "What the words mean"
        @sections = ::Reimbursements::Glossary::SECTIONS
      end
    end
  end
end
