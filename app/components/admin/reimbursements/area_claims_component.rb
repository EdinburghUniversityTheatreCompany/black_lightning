module Admin
  module Reimbursements
    ##
    # Every claim charged to an area, or to one loose budget line, under status
    # tabs, newest first.
    #
    # It answers "where has my money got to", so the status is a PLACE the claim
    # has reached rather than the stored word (see ::Reimbursements::ClaimTabs):
    # "With EUSA" beats "Submitted", which a producer reads as "I submitted it".
    #
    # An owner sees the claims but never bank details: a row carries the payee's
    # name, the amount and what it was for, nothing that would turn a show's page
    # into a directory of its members' account numbers.
    class AreaClaimsComponent < ViewComponent::Base
      # A component gets no helpers of its own (paginate included).
      delegate :reimbursements_money, :reimbursements_date, :paginate, to: :helpers

      def initialize(claims:, counts:, tab:, finance:, area: nil, budget: nil, current_person: nil)
        @claims = claims
        @counts = counts
        @tab = tab
        @finance = finance
        @area = area
        @budget = budget
        @current_person = current_person
      end

      private

      attr_reader :claims, :counts, :tab, :area, :budget, :current_person

      def finance? = @finance

      def any_claims? = counts[::Reimbursements::ClaimTabs::ALL].to_i.positive?

      def tabs = ::Reimbursements::ClaimTabs.visible(counts)

      def label_for(key) = ::Reimbursements::ClaimTabs.label(key)

      def count_for(key) = counts[key].to_i

      # Tabs are links so the tab is URL state: "my show's unpaid claims" can be
      # bookmarked and sent.
      def tab_path(key)
        params = key == ::Reimbursements::ClaimTabs::ALL ? {} : { status: key }
        if area
          helpers.admin_reimbursements_area_path(area.record_id, **params)
        else
          helpers.admin_reimbursements_budget_path(budget.record_id, **params)
        end
      end

      # Finance can open any claim on the finance edit form. A producer gets a
      # link only to a claim they submitted, and reads other rows without one, as
      # the receipt viewer does.
      def claim_path(claim)
        return helpers.edit_admin_reimbursements_expense_edit_path(claim.record_id) if finance?
        return nil if current_person.nil? || claim.person&.record_id != current_person.record_id

        helpers.admin_reimbursements_expense_path(claim.record_id)
      end

      def status_key(claim)
        ::Reimbursements::ClaimTabs::TABS.find { |_, (_, statuses)|
          statuses&.include?(claim.status)
        }&.first
      end

      def status_label(claim) = status_key(claim) ? label_for(status_key(claim)) : claim.status

      def status_classes(claim)
        case claim.status
        when ::Reimbursements::Status::PAID then "border-green-200 bg-green-50 text-success"
        when ::Reimbursements::Status::SUBMITTED then "border-blue-200 bg-blue-50 text-info"
        when ::Reimbursements::Status::APPROVED then "border-violet-200 bg-violet-50 text-violet-800"
        when ::Reimbursements::Status::PENDING then "border-amber-200 bg-amber-50 text-warning"
        when ::Reimbursements::Status::REJECTED then "border-red-200 bg-red-50 text-danger"
        else "border-gray-300 bg-white text-gray-600"
        end
      end
    end
  end
end
