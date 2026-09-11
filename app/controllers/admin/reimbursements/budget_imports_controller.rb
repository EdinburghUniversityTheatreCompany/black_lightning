module Admin
  module Reimbursements
    ##
    # Import budgets from the committee's spreadsheet. A three-step wizard,
    # deliberately the same shape as Reconcile:
    #
    #   1. show    — pick the year and the cost centre, paste the sheet or
    #                upload the xlsx.
    #   2. preview — parse and categorise (create / revise / unchanged /
    #                invalid), plus the lines already in the year that the
    #                sheet doesn't mention.
    #   3. apply   — write the lot in ONE transaction.
    #
    # STATELESS, like Reconcile: an upload is normalised to TSV on the way in
    # and carried through the preview in a hidden field, so nothing is kept in
    # the session or on disk, and apply re-parses and re-validates from scratch
    # rather than trusting what the preview decided.
    #
    # BOTH COORDINATES ARE FORM FIELDS, because a budget line is matched by name
    # within one (financial year, cost centre) and the two are orthogonal —
    # neither owns the wizard, so neither can be a path segment without hiding
    # the other. They ride the query string instead, so an entry point prefills
    # whichever side it knows (a year from the budgets index, a cost centre from
    # its settings page) and the operator picks the other.
    #
    # The year reuses FinanceController's `?year=` selector, which also scopes
    # the store — so "does this line already exist?" is asked of the year being
    # imported into, never of the year that happens to be active.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class BudgetImportsController < FinanceController
      include ReadsImportSource

      NO_COST_CENTRE_ALERT =
        "No cost centre is set up yet, so there's nothing to attach these budgets to. " \
        "Add one under Settings first.".freeze

      NO_FINANCIAL_YEAR_ALERT =
        "No financial year is set up yet, so there's nothing to import these budgets into. " \
        "Add one under Financial years first.".freeze

      NOTHING_PASTED_ALERT = "Paste the budget sheet, or choose an .xlsx file, first.".freeze

      # The page heading names NO year, deliberately. The year is a field on the
      # form now, and the <h1> sits OUTSIDE the wizard's Turbo Frame — so a
      # preview of a different year than the one the page loaded with left the
      # heading saying "Import budgets: 2026/27" above a card saying
      # "Preview: 2027/28". Each step's own heading, inside the frame, states
      # the year it is actually talking about.
      before_action -> { @title = "Import budgets" }

      # Says so up front on a portal with no years or no cost centres, rather
      # than letting the operator paste a sheet into empty selects and find out
      # at the preview step.
      def show
        destination_available?
      end

      def preview
        return render(:show) unless source_present?
        return render(:show, status: :unprocessable_entity) unless destination_available?

        build_import
        render :preview
      end

      def apply
        return redirect_to(import_path, alert: NOTHING_PASTED_ALERT) unless params[:pasted_text].present?
        return render(:show, status: :unprocessable_entity) unless destination_available?

        build_import

        # Re-validated here, not merely trusted from the preview: apply parses
        # the text afresh, so anything unreadable has to stop it a second time.
        return render_blocked_preview unless @import.valid? && selected_cost_centre

        # Areas narrowed to the ones something will actually land in: unticking
        # every re-home must not leave an empty area behind.
        re_homes = ticked_re_homes
        @result = store.import_budgets!(creates: @import.creates, revisions: @import.revisions,
                                        owner_syncs: @import.owner_syncs,
                                        area_owner_syncs: @import.area_owner_syncs,
                                        adoptions: @import.adoptions,
                                        area_creates: @import.area_creates_for(re_homes),
                                        re_homes: re_homes,
                                        note: import_note, created_by: current_user)
        render :apply
      end

      # The columns the importer reads, as an empty CSV to start from.
      def template
        send_data ::Reimbursements::BudgetImport::TSV_HEADERS.to_csv,
                  type: "text/csv", filename: "budget-import-template.csv"
      end

      private

      def build_import
        @import = ::Reimbursements::BudgetImport.new(
          import_source, input_type: input_type,
          financial_year: selected_financial_year, cost_centre: selected_cost_centre,
          existing_budgets: store.budgets_for_year, existing_areas: store.areas_for_year,
          people: store.people
        )
      end

      # Whether there is anything to import INTO at all. Distinct from "the
      # operator hasn't picked a cost centre yet", which #render_blocked_preview
      # handles: this is a portal with no years or no centres set up, where the
      # form's selects would be empty and there is nothing to choose.
      def destination_available?
        if selected_financial_year.nil?
          flash.now[:alert] = NO_FINANCIAL_YEAR_ALERT
        elsif selectable_cost_centres.empty?
          flash.now[:alert] = NO_COST_CENTRE_ALERT
        else
          return true
        end

        false
      end

      # The re-homes the operator left TICKED. The preview renders a blank
      # hidden entry beside the boxes, so the parameter is always present when
      # the bucket was shown: an absent key means unticked, never "we didn't
      # ask".
      #
      # Selected out of this apply's OWN re-parsed list, so a key matching
      # nothing here (the sheet edited between steps, the budget deleted, a
      # hand-made request) moves nothing. Unticked and unmatched both read as
      # "leave the grouping alone", as Reconcile's pair keys do.
      def ticked_re_homes
        keys = params[:re_home_budget_ids]
        return [] unless keys.is_a?(Array)

        ticked = keys.map(&:to_s).compact_blank.to_set
        @import.re_homes.select { |re_home| ticked.include?(re_home[:key].to_s) }
      end

      # Re-render the preview with the problems shown rather than redirecting:
      # a forty-line paste must survive the refusal.
      def render_blocked_preview
        flash.now[:alert] =
          if selected_cost_centre.nil?
            "Nothing was imported. Choose the cost centre these budgets belong to."
          else
            "Nothing was imported. Fix the lines flagged below and try again."
          end
        render :preview, status: :unprocessable_entity
      end

      # Names the import in the forecast history, so a figure that moved can be
      # traced back to the spreadsheet that moved it.
      def import_note
        "Imported from the budget spreadsheet on #{I18n.l(Date.current, format: :long)}"
      end

      # Both coordinates carry through "Start again" and "Cancel", so a refused
      # import comes back to the form the operator filled in, not a blank one.
      def import_path
        admin_reimbursements_budget_import_path(
          year: selected_financial_year&.key, cost_centre: selected_cost_centre&.key
        )
      end
      helper_method :import_path
    end
  end
end
