module Admin
  module Reimbursements
    ##
    # The one read behind the nominal-codes section of a cost centre's edit
    # page, shared by the page that renders it (SettingsController) and the
    # controller whose writes re-render it (NominalCodesController).
    #
    # Shared rather than written twice because the section states what
    # retiring or deleting each code would do, and that prediction has to come
    # from the same counts NominalCode#in_use? decides by — two loaders would
    # be two chances for the screen and the action to disagree.
    module ListsNominalCodes
      extend ActiveSupport::Concern

      included do
        # The section is rendered from a view in both controllers (the edit
        # page, and the turbo stream that replaces it), so the locals builder
        # has to be reachable from one.
        helper_method :nominal_codes_locals
      end

      private

      # +new_nominal_code+ carries a refused Add back to the form with the
      # typed values and its errors; a page load passes none.
      def load_nominal_codes(cost_centre, new_nominal_code: nil)
        @nominal_codes = ::Reimbursements::NominalCode.for_cost_centre(cost_centre).to_a
        @usage_counts = ::Reimbursements::NominalCode.usage_counts(cost_centre,
                                                                   @nominal_codes.map(&:code))
        @new_nominal_code = new_nominal_code || ::Reimbursements::NominalCode.new
      end

      # The locals the section partial takes. Listed once so a caller cannot
      # render it half-loaded.
      def nominal_codes_locals(cost_centre)
        { cost_centre: cost_centre, codes: @nominal_codes, usage_counts: @usage_counts,
          new_nominal_code: @new_nominal_code }
      end
    end
  end
end
