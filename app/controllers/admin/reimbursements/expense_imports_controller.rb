module Admin
  module Reimbursements
    ##
    # Import claims settled outside the portal, as a three-step wizard shaped like the
    # budget import: show (year, cost centre, paste or upload), preview (parse and
    # bucket), apply (one transaction). Stateless, see ExpenseImport. Year and cost centre
    # are form fields, not path segments: they are orthogonal, so neither can nest.
    #
    # Finance only: it writes claims in somebody else's name, at any status, with no receipt.
    class ExpenseImportsController < FinanceController
      include ReadsImportSource

      NO_COST_CENTRE_ALERT =
        "No cost centre is set up yet, so there's nothing to attach these claims to. " \
        "Add one under Settings first.".freeze

      NO_FINANCIAL_YEAR_ALERT =
        "No financial year is set up yet, so there's nothing to import these claims into. " \
        "Add one under Financial years first.".freeze

      NOTHING_PASTED_ALERT = "Paste the claims sheet, or choose an .xlsx file, first.".freeze

      NO_COST_CENTRE_CHOSEN_ALERT =
        "Choose which cost centre paid these claims. Nothing has been imported, and the sheet " \
        "you pasted is still below.".freeze

      # Deliberately does not blame a concurrent operator. An ID can also collide with a
      # stored one only under the column's collation, which folds accents where the
      # pre-flight read folds case alone, and previewing again would show the same rows
      # for ever. Naming the fix covers both.
      RACED_ALERT =
        "Nothing was imported: one of those IDs is already on a claim in the portal. " \
        "Either somebody imported this sheet while you were looking at it (preview it again " \
        "to see what is left), or an ID differs from one already imported only by an " \
        "accent, which the database counts as the same. Renaming it fixes that.".freeze

      # Names no year: the <h1> sits outside the wizard's Turbo Frame, so a preview of
      # another year would leave it disagreeing with the card. Each step's own heading names its year.
      before_action -> { @title = "Import expenses" }

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
        return redirect_to(import_path, alert: NOTHING_PASTED_ALERT) if params[:pasted_text].blank?
        return render(:show, status: :unprocessable_entity) unless destination_available?
        return render(:show, status: :unprocessable_entity) unless cost_centre_chosen?

        build_import

        return render_blocked_preview unless @import.valid?

        @created = store.import_expenses!(rows: @import.creates)
        render :apply
      rescue ActiveRecord::RecordNotUnique
        # The pre-flight read went stale; the unique index rolled the whole sheet back.
        render_blocked_preview(RACED_ALERT)
      end

      def template
        import = ::Reimbursements::ExpenseImport
        send_data import::TSV_HEADERS.to_csv + import::TEMPLATE_HINTS.to_csv,
                  type: "text/csv", filename: "expense-import-template.csv"
      end

      private

      def build_import
        @import = ::Reimbursements::ExpenseImport.new(
          import_source, input_type: input_type,
          financial_year: selected_financial_year, cost_centre: chosen_cost_centre,
          # Budgets are scoped to the destination. Expenses are NOT: an ID or expense number
          # already used must be found in any pot, or the double-apply guard has a hole.
          budgets: store.budgets_for_year, people: store.people,
          existing_expenses: store.expenses
        )
      end

      # False when no financial year or cost centre is set up, so the form's selects
      # would be empty.
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

      # Re-render the preview rather than redirecting: a forty-line paste must survive.
      def render_blocked_preview(alert = "Nothing was imported. Fix the lines flagged below and try again.")
        flash.now[:alert] = alert
        render :preview, status: :unprocessable_entity
      end

      # Both coordinates carry through "Start again" and "Cancel".
      def import_path
        admin_reimbursements_expense_import_path(
          year: selected_financial_year&.key, cost_centre: chosen_cost_centre&.key
        )
      end
      helper_method :import_path
    end
  end
end
