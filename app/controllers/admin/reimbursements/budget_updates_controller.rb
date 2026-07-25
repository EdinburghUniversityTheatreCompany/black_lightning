module Admin
  module Reimbursements
    ##
    # Multi-budget forecast revisions. One "budget update" captures a shared
    # effective date + note (e.g. the outcome of a budget meeting) and logs a
    # new forecast for each budget whose amount the operator filled in — blanks
    # are skipped. Each created forecast links back to the update, and the
    # per-budget forecast log surfaces the shared note.
    #
    # A BLANK amount means "leave this budget alone"; an amount that can't be
    # read fails the WHOLE update with a per-field error naming the budget.
    # Treating the two alike is how a budget silently keeps a superseded
    # forecast while the flash reports the other five as logged. Amounts are
    # read by Reimbursements::AmountParser, the parser the submitter form uses.
    #
    # Every failure re-renders the form with the operator's numbers intact
    # (never a redirect): 40 amounts typed after a budget meeting must not
    # evaporate because of one bad date.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class BudgetUpdatesController < FinanceController
      def index
        @title = "Budget updates"
        @budget_updates = store.budget_updates
        @budgets_by_id = store.budgets.index_by(&:record_id)
      end

      def new
        @amounts = {}
        @field_errors = {}
        set_up_form
      end

      def create
        entries = forecast_entries
        if (alert = blocking_alert(entries))
          return rerender_form(alert)
        end

        store.create_budget_update!(effective_date: @effective_date, note: params[:note].to_s,
                                    created_by: current_user, forecasts: entries)
        redirect_to admin_reimbursements_budget_updates_path,
                    notice: "Budget update saved — #{pluralize_forecasts(entries.size)} logged."
      end

      private

      def set_up_form
        @title = "New budget update"
        @effective_date ||= parse_date(params[:effective_date]) || Date.current
        @budgets = active_budgets_for_update
      end

      def rerender_form(alert)
        set_up_form
        flash.now[:alert] = alert
        render :new, status: :unprocessable_entity
      end

      # Why this update can't be written, as a flash-ready sentence, or nil when
      # it's good to go. Per-field problems are already in @field_errors for the
      # form to render beside the offending input; this is the summary line.
      # Nothing is written unless every entry is good — a partial write is how a
      # budget silently keeps a superseded forecast.
      def blocking_alert(entries)
        @effective_date = parse_date(params[:effective_date])

        if @field_errors.any?
          return "Nothing was saved. Check the amount for #{flagged_budget_names.to_sentence}."
        end
        if (stale = stale_budget_alert(entries))
          return stale
        end
        return "Nothing was saved. Enter a valid effective date." if @effective_date.nil?
        return "Enter a new amount for at least one budget." if entries.empty?

        nil
      end

      # Names of the budgets whose amount fields are flagged, so the summary line
      # says which rows to look at.
      def flagged_budget_names
        by_id = store.budgets.index_by(&:record_id)
        @field_errors.keys.map { |id| by_id[id]&.name.presence || "an unknown budget" }.sort
      end

      # A budget deleted by someone else while this form was open would otherwise
      # reach BudgetForecast's required belongs_to and 500, losing the whole
      # update. Its row is gone from the re-rendered form too, so this reports at
      # page level rather than per field; FinanceController#budget_record_id_error
      # owns the wording. Checked against the already-loaded budget list, so the
      # happy path costs no extra query however many budgets were filled in.
      def stale_budget_alert(entries)
        known = store.budgets.map(&:record_id).to_set
        stale = entries.reject { |entry| known.include?(entry[:budget_id]) }
        return nil if stale.empty?

        "Nothing was saved. #{budget_record_id_error(stale.first[:budget_id])} " \
          "Reload the form to pick up the change."
      end

      # Active budgets (income included — they carry forecasts too), named for a
      # deterministic form order.
      def active_budgets_for_update
        store.budgets.select(&:active).sort_by { |b| b.name.to_s.downcase }
      end

      # One {budget_id:, amount:} per budget whose amount field holds a readable
      # number, plus @field_errors for the ones that don't and @amounts so the
      # re-rendered form keeps what was typed. The keys are dynamic budget ids,
      # so read the nested hash directly rather than strong-param whitelisting
      # each id.
      def forecast_entries
        @amounts = params[:amounts].presence&.to_unsafe_h || {}
        @field_errors = {}

        @amounts.filter_map do |budget_id, raw|
          amount = parse_amount(budget_id.to_s, raw)
          next if amount.nil?

          { budget_id: budget_id.to_s, amount: amount }
        end
      end

      # nil for a blank field (leave that budget alone) or for an unreadable one
      # (recorded in @field_errors, which blocks the whole update).
      def parse_amount(budget_id, raw)
        ::Reimbursements::AmountParser.parse!(raw)
      rescue ::Reimbursements::AmountParser::Error
        @field_errors[budget_id] =
          "Enter a number, or leave it blank to keep the current forecast. " \
          "#{raw.to_s.strip.inspect} isn't an amount."
        nil
      end

      def pluralize_forecasts(count)
        helpers.pluralize(count, "forecast")
      end

      def parse_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end
    end
  end
end
