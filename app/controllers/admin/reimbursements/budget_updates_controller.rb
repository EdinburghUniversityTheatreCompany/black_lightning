module Admin
  module Reimbursements
    ##
    # Multi-budget forecast revisions: one shared effective date and note (e.g. a budget
    # meeting's outcome) logs a new forecast for each budget whose amount was filled in.
    #
    # A BLANK amount leaves that budget alone; an unreadable one fails the WHOLE update, since
    # treating them alike silently keeps a superseded forecast. Every failure re-renders the
    # form with the operator's numbers intact, never a redirect.
    #
    # Gated by `:manage, :reimbursements_finance` via FinanceController.
    class BudgetUpdatesController < FinanceController
      def index
        @title = "Budget updates"
        @budget_updates = store.budget_updates
        @budgets_by_id = store.budgets.index_by(&:record_id)
        # Names only, so skip store.areas' preloads. Unscoped, so last year's line or area is
        # still named.
        @area_names_by_id = store.area_names_by_id
      end

      def show
        @budget_update = find_or_404(:find_budget_update)
        @title = "Budget update: #{helpers.reimbursements_date(@budget_update.effective_date)}"
        @rows = revision_rows(@budget_update)
      end

      # The forecasts are destroyed rather than detached (DatabaseStore#delete_budget_update!),
      # so each line falls back to the forecast before this one.
      def destroy
        budget_update = find_or_404(:find_budget_update)
        count = budget_update.forecasts.size
        store.delete_budget_update!(budget_update.record_id)
        redirect_to admin_reimbursements_budget_updates_path,
                    notice: "Removed that budget update. #{pluralize_forecasts(count)} " \
                            "#{count == 1 ? 'was' : 'were'} undone, so each line is back on the " \
                            "forecast it had before."
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
                    notice: "Budget update saved: #{pluralize_forecasts(entries.size)} logged."
      end

      private

      # "Replaced" is the line's newest forecast ordered before this one, the order
      # current_forecast reads, so it is what removing this update falls back to. Nil for a
      # first forecast, which falls back to the initial budget. "Now" is read separately
      # because a later revision may already have superseded this one.
      def revision_rows(budget_update)
        budget_update.forecasts.sort_by { |f| label_for(f).to_s.downcase }.map do |forecast|
          owner = forecast.budget || forecast.area
          { label: label_for(forecast), area_total: forecast.budget_id.nil?,
            amount: forecast.amount, replaced: previous_forecast(forecast)&.amount,
            initial: owner&.initial_budget, current: owner&.current_forecast,
            superseded: superseded?(forecast, owner) }
        end
      end

      def label_for(forecast)
        return forecast.budget.display_name if forecast.budget
        return "#{forecast.area.name} (area total)" if forecast.area

        "an unknown line"
      end

      def previous_forecast(forecast)
        # Array has <=> but not <, so the comparison has to be spelled out.
        siblings_of(forecast)
          .select { |other| (sort_key(other) <=> sort_key(forecast)).negative? }
          .max_by { |other| sort_key(other) }
      end

      def superseded?(forecast, owner)
        return false if owner.nil?

        siblings_of(forecast).any? { |other| (sort_key(other) <=> sort_key(forecast)).positive? }
      end

      def siblings_of(forecast)
        owner = forecast.budget || forecast.area
        return [] if owner.nil?

        owner.forecasts.to_a
      end

      def sort_key(forecast)
        [ forecast.date || Date.new(0), forecast.id ]
      end

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

      # The flash summary line, or nil when the update is good to go. Per-field problems are
      # already in @field_errors. Nothing is written unless every entry is good: a partial
      # write silently leaves a budget on a superseded forecast.
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

      # display_name, so identically-named lines on the form can be told apart.
      def flagged_budget_names
        by_id = store.budgets.index_by(&:record_id)
        @field_errors.keys.map { |id| by_id[id]&.display_name.presence || "an unknown budget" }.sort
      end

      # A budget deleted while the form was open would hit BudgetForecast's required
      # belongs_to and 500, losing the whole update. Checked against the already-loaded list,
      # so the happy path costs no extra query.
      def stale_budget_alert(entries)
        known = store.budgets.map(&:record_id).to_set
        stale = entries.reject { |entry| known.include?(entry[:budget_id]) }
        return nil if stale.empty?

        "Nothing was saved. #{budget_record_id_error(stale.first[:budget_id])} " \
          "Reload the form to pick up the change."
      end

      # Income lines included (they carry forecasts too). Scoped to the selected year so a
      # meeting can't re-forecast last year's closed lines.
      def active_budgets_for_update
        store.budgets_for_year.select(&:active).sort_by { |b| b.display_name.to_s.downcase }
      end

      # The keys are dynamic budget ids, so the nested hash is read directly rather than
      # strong-param whitelisted. @amounts keeps what was typed for the re-render.
      def forecast_entries
        @amounts = params[:amounts].presence&.to_unsafe_h || {}
        @field_errors = {}

        @amounts.filter_map do |budget_id, raw|
          amount = parse_amount(budget_id.to_s, raw)
          next if amount.nil?

          { budget_id: budget_id.to_s, amount: amount }
        end
      end

      # nil for a blank field (leave alone) or an unreadable one (recorded in @field_errors).
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
