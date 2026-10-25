module Admin
  module Reimbursements
    ##
    # The top of an import wizard's preview step, shared by the budget and expense imports:
    # Start again, the alert, the card naming where the rows would go, and what stops the import
    # (each unusable row, then the sheet's own errors). The step's own content follows inside the
    # card. Renders inside the wizard's Turbo Frame, which the caller opens.
    class ImportPreviewComponent < ViewComponent::Base
      # One per row the import cannot use: the row's identifier and why, as that wizard words it.
      renders_many :invalid_rows

      # +alert+ is the flash alert: the layout's flash sits outside the frame, so a frame-only
      # response would never show it. +invalid_verb+ completes "3 rows can't be ___, so nothing
      # can be imported yet". +errors+ are the import's whole-sheet errors.
      def initialize(back_path:, alert:, financial_year:, cost_centre:, invalid_verb:, errors:)
        @back_path = back_path
        @alert = alert
        @financial_year = financial_year
        @cost_centre = cost_centre
        @invalid_verb = invalid_verb
        @errors = errors
      end

      private

      attr_reader :back_path, :alert, :invalid_verb, :errors

      # Names both coordinates: the page <h1> sits outside the frame, so it still says whatever
      # the page loaded with.
      def title = "Preview: #{@financial_year.label} · #{@cost_centre&.name}"
    end
  end
end
