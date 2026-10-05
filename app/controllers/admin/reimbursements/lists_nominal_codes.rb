module Admin
  module Reimbursements
    ##
    # Loads the nominal-codes section for the controller that renders it and the
    # one whose writes re-render it, so both predict Retire/Delete the same way.
    module ListsNominalCodes
      extend ActiveSupport::Concern

      included do
        helper_method :nominal_codes_locals
      end

      private

      # +new_nominal_code+ carries a refused Add back with its typed values and errors.
      def load_nominal_codes(cost_centre, new_nominal_code: nil)
        @nominal_codes = ::Reimbursements::NominalCode.for_cost_centre(cost_centre).to_a
        @usage_counts = ::Reimbursements::NominalCode.usage_counts(cost_centre,
                                                                   @nominal_codes.map(&:code))
        @new_nominal_code = new_nominal_code || ::Reimbursements::NominalCode.new
      end

      # Listed once so a caller cannot render the section half-loaded.
      def nominal_codes_locals(cost_centre)
        { cost_centre: cost_centre, codes: @nominal_codes, usage_counts: @usage_counts,
          new_nominal_code: @new_nominal_code }
      end
    end
  end
end
