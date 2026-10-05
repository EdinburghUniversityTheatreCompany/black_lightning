module Admin
  module Reimbursements
    ##
    # Imports the committee's budget spreadsheet: show (year, cost centre and
    # the sheet), preview, then apply in one transaction. Stateless, like
    # Reconcile: the preview carries the sheet on as canonical TSV.
    class BudgetImportsController < FinanceController
      include ReadsImportSource

      NO_COST_CENTRE_ALERT =
        "No cost centre is set up yet, so there's nothing to attach these budgets to. " \
        "Add one under Settings first.".freeze

      NO_FINANCIAL_YEAR_ALERT =
        "No financial year is set up yet, so there's nothing to import these budgets into. " \
        "Add one under Financial years first.".freeze

      NOTHING_PASTED_ALERT = "Paste the budget sheet, or choose an .xlsx file, first.".freeze

      NO_COST_CENTRE_CHOSEN_ALERT =
        "Choose which cost centre these budgets belong to. Nothing has been imported, and the " \
        "sheet you pasted is still below.".freeze

      # Names no year: the <h1> sits outside the wizard's Turbo Frame, so it
      # would go stale when a preview names another year. Each step's own
      # heading names it.
      before_action -> { @title = "Import budgets" }

      # Flags a portal with no years or centres before anything is pasted.
      def show
        destination_available?
      end

      def preview
        return render(:show) unless source_present?
        return render(:show, status: :unprocessable_entity) unless destination_available?
        return render(:show, status: :unprocessable_entity) unless cost_centre_chosen?

        build_import
        render :preview
      end

      def apply
        return redirect_to(import_path, alert: NOTHING_PASTED_ALERT) unless params[:pasted_text].present?
        return render(:show, status: :unprocessable_entity) unless destination_available?
        return render(:show, status: :unprocessable_entity) unless cost_centre_chosen?

        build_import

        # Re-validated, not trusted from the preview: apply parses afresh.
        return render_blocked_preview unless @import.valid?

        re_homes = ticked_re_homes
        @result = store.import_budgets!(creates: @import.creates, revisions: @import.revisions,
                                        owner_syncs: @import.owner_syncs,
                                        area_owner_syncs: @import.area_owner_syncs,
                                        adoptions: @import.adoptions,
                                        area_creates: @import.area_creates_for(re_homes),
                                        area_revisions: @import.area_revisions,
                                        re_homes: re_homes,
                                        note: import_note, created_by: current_user)
        render :apply
      end

      # The columns the importer reads plus a hint row, which it skips.
      def template
        import = ::Reimbursements::BudgetImport
        send_data import::TSV_HEADERS.to_csv + import::TEMPLATE_HINTS.to_csv,
                  type: "text/csv", filename: "budget-import-template.csv"
      end

      private

      def build_import
        @import = ::Reimbursements::BudgetImport.new(
          import_source, input_type: input_type,
          financial_year: selected_financial_year, cost_centre: chosen_cost_centre,
          existing_budgets: store.budgets_for_year, existing_areas: store.areas_for_year,
          people: store.people
        )
      end

      # Whether there is anything to import INTO. Distinct from no centre picked
      # yet (#cost_centre_chosen?): this is a portal with no years or centres.
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

      # The preview always posts a blank entry, so an absent key is a real
      # untick. Selected from this apply's own re-parsed list, so a key that
      # matches nothing here moves nothing.
      def ticked_re_homes
        keys = params[:re_home_budget_ids]
        return [] unless keys.is_a?(Array)

        ticked = keys.map(&:to_s).compact_blank.to_set
        @import.re_homes.select { |re_home| ticked.include?(re_home[:budget_id].to_s) }
      end

      # Re-rendered rather than redirected, so a forty-line paste survives.
      def render_blocked_preview
        flash.now[:alert] = "Nothing was imported. Fix the lines flagged below and try again."
        render :preview, status: :unprocessable_entity
      end

      def import_note
        "Imported from the budget spreadsheet on #{I18n.l(Date.current, format: :long)}"
      end

      # Both coordinates carry through "Start again" and "Cancel".
      def import_path
        admin_reimbursements_budget_import_path(
          year: selected_financial_year&.key, cost_centre: chosen_cost_centre&.key
        )
      end
      helper_method :import_path
    end
  end
end
