module Admin
  module Reimbursements
    ##
    # Import a financial year's budgets from the committee's spreadsheet. A
    # three-step wizard, deliberately the same shape as Reconcile:
    #
    #   1. show    — pick the cost centre, paste the sheet or upload the xlsx.
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
    # The year comes from the URL, not the ?year= selector, and the store is
    # scoped to it — so "does this line already exist?" is asked of the year
    # being imported into, never of the year that happens to be active.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class BudgetImportsController < FinanceController
      NO_COST_CENTRE_ALERT =
        "No cost centre is set up yet, so there's nothing to attach these budgets to. " \
        "Add one under Settings first.".freeze

      NOTHING_PASTED_ALERT = "Paste the budget sheet, or choose an .xlsx file, first.".freeze

      def show
        @title = "Import budgets: #{@financial_year.label}"
      end

      def preview
        @title = "Import budgets: #{@financial_year.label}"
        return render(:show) unless source_present?

        if cost_centres.empty?
          flash.now[:alert] = NO_COST_CENTRE_ALERT
          return render(:show)
        end

        build_import
        render :preview
      end

      def apply
        @title = "Import budgets: #{@financial_year.label}"
        return redirect_to(import_path, alert: NOTHING_PASTED_ALERT) unless params[:pasted_text].present?

        build_import

        # Re-validated here, not merely trusted from the preview: apply parses
        # the text afresh, so anything unreadable has to stop it a second time.
        return render_blocked_preview unless @import.valid? && selected_cost_centre

        @result = store.import_budgets!(creates: @import.creates, revisions: @import.revisions,
                                        owner_syncs: @import.owner_syncs, note: import_note,
                                        created_by: current_user)
        render :apply
      end

      # The columns the importer reads, as an empty CSV to start from.
      def template
        send_data ::Reimbursements::BudgetImport::TSV_HEADERS.to_csv,
                  type: "text/csv", filename: "budget-import-template.csv"
      end

      private

      # The year being imported into owns this whole request, INCLUDING the
      # store's scope — so #budgets_for_year below is this year's lines.
      def resolve_financial_year!
        @financial_year = ::Reimbursements::FinancialYear.find_by!(key: params[:financial_year_key])
        @selected_financial_year = @financial_year
      end

      def build_import
        @import = ::Reimbursements::BudgetImport.new(
          import_source, input_type: input_type,
          financial_year: @financial_year, cost_centre: selected_cost_centre,
          existing_budgets: store.budgets_for_year, people: store.people
        )
      end

      # An uploaded file on this request, otherwise the pasted (or carried-over)
      # text. Apply only ever sees text: the preview carried the upload on.
      def import_source
        uploaded_file || params[:pasted_text].to_s
      end

      def input_type = uploaded_file ? :xlsx : :paste

      def uploaded_file
        file = params[:file]
        file.respond_to?(:path) ? file : nil
      end

      def source_present?
        return true if uploaded_file
        return true if params[:pasted_text].to_s.strip.present?

        flash.now[:alert] = NOTHING_PASTED_ALERT
        false
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

      def selected_cost_centre
        return @selected_cost_centre if defined?(@selected_cost_centre)

        @selected_cost_centre = cost_centres.find { |centre| centre.id.to_s == params[:cost_centre_id].to_s }
      end
      helper_method :selected_cost_centre

      def cost_centres
        @cost_centres ||= ::Reimbursements::CostCentre.order(:name).to_a
      end
      helper_method :cost_centres

      # Names the import in the forecast history, so a figure that moved can be
      # traced back to the spreadsheet that moved it.
      def import_note
        "Imported from the budget spreadsheet on #{I18n.l(Date.current, format: :long)}"
      end

      def import_path
        admin_reimbursements_financial_year_budget_import_path(@financial_year.key)
      end
      helper_method :import_path
    end
  end
end
