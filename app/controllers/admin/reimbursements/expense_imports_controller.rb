module Admin
  module Reimbursements
    ##
    # Import claims that were settled outside the portal — the years finance
    # ran on a spreadsheet, or a pot the portal only took over halfway through.
    # A three-step wizard, deliberately the same shape as the budget import:
    #
    #   1. show    — pick the year and the cost centre, paste the sheet or
    #                upload the xlsx.
    #   2. preview — parse and categorise (create / already imported / invalid).
    #   3. apply   — write the lot in ONE transaction.
    #
    # STATELESS: an upload is normalised to TSV on the way in and carried
    # through the preview in a hidden field, so nothing is kept in the session
    # or on disk, and apply re-parses and re-validates from scratch rather than
    # trusting what the preview decided.
    #
    # THAT IS ALSO WHY THE SHEET NEEDS A REFERENCE COLUMN. Re-posting the same
    # text is what a second click does, and a claim has no natural key the way
    # a budget line has its name — see ExpenseImport, and the unique index on
    # expenses.import_key that backs it.
    #
    # BOTH COORDINATES ARE FORM FIELDS, as they are on the budget import: a
    # claim is charged to a budget matched by name within one (financial year,
    # cost centre), and the two are orthogonal, so neither can be a path
    # segment without hiding the other from the entry points that know it.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController. Producers never see this: it writes claims in
    # somebody else's name, at any status, with no receipt.
    class ExpenseImportsController < FinanceController
      include ReadsImportSource

      NO_COST_CENTRE_ALERT =
        "No cost centre is set up yet, so there's nothing to attach these claims to. " \
        "Add one under Settings first.".freeze

      NO_FINANCIAL_YEAR_ALERT =
        "No financial year is set up yet, so there's nothing to import these claims into. " \
        "Add one under Financial years first.".freeze

      NOTHING_PASTED_ALERT = "Paste the claims sheet, or choose an .xlsx file, first.".freeze

      # Deliberately does NOT assert what happened. Two things reach here: a
      # genuine race (somebody imported the same sheet meanwhile), and a
      # reference that collides with one already stored only under the column's
      # utf8mb4_unicode_ci collation — which folds ACCENTS as well as case,
      # while the pre-flight read folds case alone. Blaming a concurrent
      # operator for the second is a dead end: previewing again shows the same
      # rows and the import can never succeed. Naming the fix covers both.
      RACED_ALERT =
        "Nothing was imported: one of those references is already on a claim in the portal. " \
        "Either somebody imported this sheet while you were looking at it — preview it again " \
        "to see what is left — or a reference differs from one already imported only by an " \
        "accent, which the database counts as the same. Renaming it fixes that.".freeze

      # Names no year, for the same reason the budget import's doesn't: the
      # <h1> sits OUTSIDE the wizard's Turbo Frame, so a preview of a different
      # year than the page loaded with would leave the heading and the card
      # stating different years. Each step's own heading, inside the frame,
      # names the year it is actually talking about.
      before_action -> { @title = "Import expenses" }

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
        return redirect_to(import_path, alert: NOTHING_PASTED_ALERT) if params[:pasted_text].blank?
        return render(:show, status: :unprocessable_entity) unless destination_available?

        build_import

        # Re-validated here, not merely trusted from the preview: apply parses
        # the text afresh, so anything unreadable has to stop it a second time.
        return render_blocked_preview unless @import.valid? && selected_cost_centre

        @created = store.import_expenses!(rows: @import.creates)
        render :apply
      rescue ActiveRecord::RecordNotUnique
        # The pre-flight "already imported" read went stale between this
        # request's parse and its write. The unique index caught it and the
        # transaction rolled the whole sheet back, which is the point.
        render_blocked_preview(RACED_ALERT)
      end

      # The columns the importer reads, as an empty CSV to start from.
      def template
        send_data ::Reimbursements::ExpenseImport::TSV_HEADERS.to_csv,
                  type: "text/csv", filename: "expense-import-template.csv"
      end

      private

      def build_import
        @import = ::Reimbursements::ExpenseImport.new(
          import_source, input_type: input_type,
          financial_year: selected_financial_year, cost_centre: selected_cost_centre,
          # Scoped to the destination, so "which budget is this?" is asked of
          # the year and pot being imported into rather than of whichever
          # happens to be active. Expenses are NOT scoped: an already-used
          # reference or expense number must be found wherever it lives, or the
          # double-apply guard has a hole exactly the size of the other pot.
          budgets: store.budgets_for_year, people: store.people,
          existing_expenses: store.expenses
        )
      end

      # Whether there is anything to import INTO at all — a portal with no
      # years or no centres set up, where the form's selects would be empty and
      # there is nothing to choose. Distinct from "the operator hasn't picked a
      # cost centre yet", which #render_blocked_preview handles.
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

      # Re-render the preview with the problems shown rather than redirecting:
      # a forty-line paste must survive the refusal.
      def render_blocked_preview(alert = nil)
        flash.now[:alert] = alert ||
                            if selected_cost_centre.nil?
                              "Nothing was imported. Choose the cost centre these claims belong to."
                            else
                              "Nothing was imported. Fix the lines flagged below and try again."
                            end
        render :preview, status: :unprocessable_entity
      end

      # Both coordinates carry through "Start again" and "Cancel", so a refused
      # import comes back to the form the operator filled in, not a blank one.
      def import_path
        admin_reimbursements_expense_import_path(
          year: selected_financial_year&.key, cost_centre: selected_cost_centre&.key
        )
      end
      helper_method :import_path
    end
  end
end
