module Admin
  module Reimbursements
    ##
    # Finance's budget screens: index, overview, the edit form and its forecast
    # log. #show is also open to the line's own owners.
    class BudgetsController < FinanceController
      include ListsClaims

      # A loose line's page is also open to its owners, who hold no finance
      # permission (the same union and 404 as an area's page).
      skip_before_action :authorize_finance!, only: %i[show]
      before_action :authorize_budget_page!, only: %i[show]
      before_action :set_budget, only: %i[edit update forecast update_forecast delete_forecast]
      before_action :set_forecast, only: %i[update_forecast delete_forecast]

      def show
        @title = @budget.name
        @summary = ::Reimbursements::SpendSummary.for_budget(@budget)
        load_claims([ @budget ])
      end

      def index
        @title = "Reimbursements Budgets"
        # budgets_with_actuals: this table and its CSV print each line's EUSA actual.
        budgets = store.budgets_with_actuals
        # Area figures are read off these preloaded objects, never off
        # budget.area, whose unloaded #budgets would N+1.
        @areas_by_id = store.areas.index_by(&:record_id)
        respond_to do |format|
          # Not paginated: a page boundary split an area's lines across pages.
          format.html { @budgets = ::Reimbursements::Budget.index_order(budgets) }
          format.csv { send_export ::Reimbursements::Exports::Budgets, budgets.sort_by { |budget| budget.name.to_s.downcase } }
        end
      end

      # The same budgets by nominal code and by area, plus the EUSA ledger rows
      # no budget accounts for.
      def overview
        @title = "Budget overview"
        grouped = store.budgets_by_nominal_code
        budgets = grouped.values.flatten
        @rollups = grouped.map { |code, group| ::Reimbursements::NominalCodeRollup.new(code, group) }
        @grand_total = ::Reimbursements::NominalCodeRollup.new(nil, budgets)
        build_area_rollups(budgets)
        unattributed = store.unattributed_actuals
        @unattributed_by_code = unattributed.group_by do |actual|
          actual.nominal_code.presence || ::Reimbursements::DatabaseStore::NO_CODE_LABEL
        end
        # Over the same scoped budgets the cards total, so the summary counts
        # only lines the tables show.
        @over_budget_count = budgets.count(&:over_budget?)
        # A count beside the net, which is debits less credits and can
        # legitimately be negative.
        @unattributed_count = unattributed.size
        @unattributed_total = ::Reimbursements::EusaActual.net(unattributed)
      end

      # One line by hand; a whole year comes in through the budget import.
      def new
        @title = "New budget"
        @people = store.people
        # Every centre's areas for the year: the browser narrows the list to the
        # centre picked (reimbursements-budget-area#costCentreChanged) and
        # area_scope_error refuses a mismatch that gets past it.
        @areas = assignable_areas(year: selected_financial_year)
      end

      def create
        new_budget = ::Reimbursements::Budget.new(budget_type: "Expense")
        attrs = budget_params(new_budget)
        if (error = budget_validation_error(attrs, new_budget))
          new
          flash.now[:alert] = error
          return render(:new, status: :unprocessable_entity)
        end

        budget = store.create_budget!(attrs.merge(financial_year: selected_financial_year,
                                                  cost_centre: chosen_cost_centre))
        # The centre the form picked, so the edit page and its back link show the line.
        scope = scope_params
        scope[:cost_centre] = chosen_cost_centre.key if params[:cost_centre_id].present?
        redirect_to edit_admin_reimbursements_budget_path(budget.record_id, **scope), notice: "Budget created."
      end

      def edit
        @title = "Budget: #{@budget.display_name}"
        @people = store.people
        # The areas area_scope_error accepts for this line, plus its own area
        # always: area_id writes unscoped, so an unrendered area made any Save
        # nil the link.
        @areas = (assignable_areas(year: @budget.financial_year, centre: @budget.cost_centre) +
                  [ @budget.area ]).compact.uniq
        @forecasts = store.budget_forecasts(@budget.record_id)
        # ?edit_forecast=<id> renders that row as an inline edit form.
        @editing_forecast_id = params[:edit_forecast].presence
        @previous_budget, @next_budget = neighbours(@budget)
      end

      def update
        attrs = budget_params
        if (error = budget_validation_error(attrs))
          return redirect_to(edit_path, alert: error)
        end

        store.update_budget!(@budget.record_id, attrs)
        # ?budget= as well as the fragment: Turbo follows the redirect with
        # fetch and drops the fragment, so scroll_to_controller reads the param.
        redirect_to admin_reimbursements_budgets_path(**scope_params, budget: @budget.record_id,
                                                                      anchor: "budget_#{@budget.record_id}"),
                    notice: "Budget saved."
      end

      # Appends a projected-spend update (amount + date + reason) to this budget;
      # the newest one becomes its current forecast.
      def forecast
        return unless (attrs = forecast_attrs)

        store.create_forecast!(budget_id: @budget.record_id, **attrs)
        redirect_to edit_path, notice: "Forecast added."
      end

      # Correct a forecast logged in error.
      def update_forecast
        return unless (attrs = forecast_attrs)

        store.update_forecast!(@forecast.record_id, **attrs)
        redirect_to edit_path, notice: "Forecast updated."
      end

      def delete_forecast
        store.delete_forecast!(@forecast.record_id)
        redirect_to edit_path, notice: "Forecast removed."
      end

      private

      # The codes the form suggests and the overview's labels, for the selected
      # cost centre (none selected means every centre).
      def nominal_code_suggestions
        @nominal_code_suggestions ||=
          ::Reimbursements::NominalCode.suggestions_for(selected_cost_centre)
      end
      helper_method :nominal_code_suggestions

      def nominal_code_labels
        @nominal_code_labels ||=
          ::Reimbursements::NominalCode.labels_for(selected_cost_centre)
      end
      helper_method :nominal_code_labels

      # The budgets the nominal-code card totals, regrouped by area. Areas come
      # from store.areas, never budget.area, whose unloaded #budgets would N+1.
      def build_area_rollups(budgets)
        areas_by_id = store.areas.index_by(&:record_id)
        by_area_id = budgets.group_by { |budget| budget.area&.record_id }
        unassigned = by_area_id.delete(nil)
        @area_rollups = by_area_id
                        .map { |id, group| ::Reimbursements::AreaRollup.new(area: areas_by_id[id], budgets: group) }
                        .sort_by { |rollup| rollup.name.to_s.downcase }
        # Nil, not empty, so no "Not in an area" heading renders when every
        # line has an area.
        @unassigned_rollup = unassigned && ::Reimbursements::AreaRollup.new(area: nil, budgets: unassigned)
      end

      # A forecast id arriving in the URL must actually belong to this budget,
      # or one budget's page could mutate another's forecast log.
      def set_forecast
        @forecast = store.budget_forecasts(@budget.record_id).find { |f| f.record_id == params[:forecast_id] }
        redirect_to edit_path, alert: "That forecast isn't part of this budget." unless @forecast
      end

      # The forecast form's fields, or nil after redirecting when the amount or
      # date is unreadable.
      def forecast_attrs
        amount = ::Reimbursements::AmountParser.parse(params[:amount])
        date = parse_date(params[:date])
        return { amount: amount, date: date, reason: params[:reason].to_s } if amount && date

        redirect_to edit_path, alert: "Enter a valid amount and date for the forecast."
        nil
      end

      def authorize_budget_page!
        @budget = owner_page_record(:find_budget)
      end

      def set_budget
        @budget = find_or_404(:find_budget)
      end

      def edit_path
        edit_admin_reimbursements_budget_path(@budget.record_id, **scope_params)
      end

      # The lines either side of +budget+ in the index's order, nil at the ends
      # or when the line is outside the page's year and centre.
      def neighbours(budget)
        list = ::Reimbursements::Budget.index_order(store.budgets_for_year)
        index = list.index { |other| other.record_id == budget.record_id }
        return [ nil, nil ] if index.nil?

        [ (list[index - 1] if index.positive?), list[index + 1] ]
      end

      # No form object backs this write, so the checks that tell the operator
      # what is wrong live here.
      def budget_validation_error(attrs, budget = @budget)
        return "Enter a budget name." if attrs[:name].blank?
        return "Enter a nominal code." if attrs[:nominal_code].blank?
        unless ::Reimbursements::Budget::TYPES.include?(attrs[:budget_type])
          return "Choose a valid budget type."
        end

        owners_in_area_error(budget) || area_scope_error(attrs, budget) ||
          owner_ids_error(attrs[:owner_ids])
      end

      # A line in an area must share the area's cost centre and year
      # (inherit_area_scoping fills blanks only, and #create always sets a
      # centre). Refused, never re-homed: moving the line to the area's centre
      # would move money between pots on a Save about a name.
      def area_scope_error(attrs, budget)
        return nil unless attrs.key?(:area_id)

        area = attrs[:area_id].present? && store.find_area(attrs[:area_id])
        return nil unless area

        centre = budget.persisted? ? budget.cost_centre : chosen_cost_centre
        year = budget.persisted? ? budget.financial_year : selected_financial_year

        mismatch_error("cost centre", area.cost_centre&.name, centre&.name) ||
          mismatch_error("financial year", area.financial_year&.label, year&.label)
      end

      # Lenient like mismatch_error (an unset side matches anything), so the
      # picker never offers an area the Save refuses.
      def assignable_areas(year:, centre: nil)
        store.areas.select do |area|
          lenient_match?(area.financial_year_id, year&.id) &&
            lenient_match?(area.cost_centre_id, centre&.id)
        end
      end

      def lenient_match?(area_value, budget_value)
        area_value.nil? || budget_value.nil? || area_value == budget_value
      end

      # Nil when either side is unset: an unstamped area or line belongs to
      # every centre and year, and inheritance fills the blank.
      def mismatch_error(label, area_value, budget_value)
        return nil if area_value.blank? || budget_value.blank? || area_value == budget_value

        "That area is in a different #{label} (#{area_value}) from this budget " \
          "(#{budget_value}). Pick an area from #{budget_value}, or leave Area blank."
      end

      # Owners ticked for a line going into an area would land in own_owners,
      # which Budget#owners never reads once there is an area, so they are
      # refused. A line already in an area renders no list, and what a stale
      # page posts is ignored (budget_params drops the key).
      def owners_in_area_error(budget)
        return nil if budget.area_id || posted_area_id.blank?
        return nil if Array(params[:owner_ids]).reject(&:blank?).empty?

        "A line in an area takes its owners from the area, so the people ticked here would " \
          "never be read. Untick them and set them on the area, or leave Area blank."
      end

      # +active+ is a checkbox, so absence means off. A blank or unreadable
      # initial_budget is left out, so it cannot zero the figure.
      def budget_params(budget = @budget)
        attrs = {
          name: params[:name].to_s.strip,
          nominal_code: params[:nominal_code].to_s.strip,
          notes: params[:notes].to_s,
          budget_type: params[:budget_type].presence || budget.budget_type,
          active: params[:active].present?
        }
        # An absent area_id means no change (the form offered no picker); a
        # posted "" is the "No area" option, a deliberate detach.
        attrs[:area_id] = params[:area_id].presence if params.key?(:area_id)
        # Ownership is edited on the area. For a line in (or going into) one,
        # omit the KEY rather than send []: syncing would rewrite the own rows
        # the backfill keeps, and an empty list is where.not(person_id: []),
        # i.e. WHERE 1=1. Read the area being GIVEN, not only the record's:
        # #create's Budget.new has area_id nil.
        unless budget.area_id || posted_area_id.present?
          attrs[:owner_ids] = Array(params[:owner_ids]).reject(&:blank?)
        end
        # Lenient like the submitter form: "£1,200" and "12,50" are amounts.
        initial = ::Reimbursements::AmountParser.parse(params[:initial_budget])
        attrs[:initial_budget] = initial unless initial.nil?
        attrs
      end

      def posted_area_id
        params[:area_id].presence
      end

      # The form's cost_centre_id first: the form URL carries the page's ?cost_centre=, which
      # resolve_cost_centre! prefers, and the form's choice must win over the page's.
      def chosen_cost_centre
        ::Reimbursements::CostCentre.find_by(id: params[:cost_centre_id]) ||
          selected_cost_centre || ::Reimbursements::CostCentre.default
      end
    end
  end
end
