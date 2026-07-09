module Reimbursements
  module Airtable
    ##
    # Raised for non-2xx Airtable API responses (after the single 429 retry).
    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end
  end
end
