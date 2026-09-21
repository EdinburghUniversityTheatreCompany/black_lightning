module Admin
  module Reimbursements
    ##
    # Every claim charged to an area, under status tabs, newest first.
    #
    # This is the half of the page that answers "where has my money got to",
    # which today has no answer anywhere in the portal for anyone but finance.
    # So the status is written as a PLACE the claim has reached rather than as
    # the stored word (see ::Reimbursements::ClaimTabs): "With EUSA" beats
    # "Submitted", which a producer reads as "I submitted it".
    #
    # An owner sees the claims but never bank details: the row carries the
    # payee's NAME, the amount and what it was for, which is what sign-off and
    # "has mine been paid" need, and nothing that would turn a show's page into
    # a directory of its members' account numbers.
    class AreaClaimsComponent < ViewComponent::Base
      # A component gets no helpers of its own, and these two are how every
      # money figure and date in this portal is written.
      delegate :reimbursements_money, :reimbursements_date, to: :helpers

      def initialize(claims:, counts:, tab:, finance:, area: nil, current_person: nil)
        @claims = claims
        @counts = counts
        @tab = tab
        @finance = finance
        @area = area
        @current_person = current_person
      end

      private

      attr_reader :claims, :counts, :tab, :area, :current_person

      def finance? = @finance

      def any_claims? = counts[::Reimbursements::ClaimTabs::ALL].to_i.positive?

      def tabs = ::Reimbursements::ClaimTabs.visible(counts)

      def label_for(key) = ::Reimbursements::ClaimTabs.label(key)

      def count_for(key) = counts[key].to_i

      # Tabs are links, not JavaScript: the tab is URL state like every other
      # filter in this portal, so a producer can bookmark "my show's unpaid
      # claims" and finance can send one.
      def tab_path(key)
        params = key == ::Reimbursements::ClaimTabs::ALL ? {} : { status: key }
        helpers.admin_reimbursements_area_path(area.record_id, **params)
      end

      # Finance can open any claim on the finance edit form. A producer gets a
      # link only to a claim they submitted themselves — their own claim's page
      # is theirs to see — and otherwise reads the row without a link, which is
      # the same rule the receipt viewer already applies.
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
