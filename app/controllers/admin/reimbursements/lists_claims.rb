module Admin
  module Reimbursements
    ##
    # The claims table an area's page and a loose line's page both render.
    module ListsClaims
      extend ActiveSupport::Concern

      # Shorter than the finance lists' 50: the question ("where has mine got to") is
      # answered near the top.
      CLAIMS_PAGE_SIZE = 25

      private

      # Claims charged to any of these lines, newest first. Reads the store's one
      # preloaded expense list rather than a query per line. A draft keeps its budget
      # but is the submitter's alone (see ClaimTabs), so it is left out.
      def claims_for_lines(lines)
        ids = Array(lines).map(&:record_id).to_set
        store.expenses
             .select { |expense| ids.include?(expense.budget&.record_id) && expense.status != ::Reimbursements::Status::DRAFT }
             .sort_by { |expense| [ expense.submitted_at || Time.at(0), expense.auto_number.to_i ] }
             .reverse
      end

      # An owner sees their own line or area; finance sees all. 404, not 403, so a stranger
      # cannot tell the record exists.
      def owner_page_record(finder)
        record = store.public_send(finder, params[:id])
        visible = record && (can?(:manage, :reimbursements_finance) ||
                             (current_person.present? && record.owner_ids.include?(current_person.record_id)))
        raise ActiveRecord::RecordNotFound unless visible

        record
      end

      # Tab counts come from the whole list, before filtering.
      def load_claims(lines)
        claims = claims_for_lines(lines)
        @claim_counts = ::Reimbursements::ClaimTabs.counts(claims)
        @claim_tab = ::Reimbursements::ClaimTabs.resolve(params[:status])
        @claims = paginate(::Reimbursements::ClaimTabs.filter(claims, @claim_tab), per: CLAIMS_PAGE_SIZE)
      end
    end
  end
end
