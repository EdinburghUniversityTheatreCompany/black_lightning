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

      def show
        @title = @budget.name
        @summary = ::Reimbursements::SpendSummary.for_budget(@budget)
        load_claims([ @budget ])
        @changes = ::Reimbursements::BudgetChanges.for_budget(@budget)
      end

      def index
        @title = "Reimbursements Budgets"
        # budgets_with_actuals: this table and its CSV print each line's EUSA actual.
        sorted = store.budgets_with_actuals.sort_by { |budget| budget.name.to_s.downcase }
        @people_by_id = store.people.index_by(&:record_id)
        # Area figures are read off these preloaded objects, never off
        # budget.area, whose unloaded #budgets would N+1.
        @areas_by_id = store.areas.index_by(&:record_id)
        respond_to do |format|
          # Not paginated: a page boundary split an area's lines across pages.
          format.html { @budgets = sorted }
          format.csv { send_export ::Reimbursements::Exports::Budgets, sorted }
        end
      end

      # The same budgets by nominal code and by area, plus the EUSA ledger rows
      # no budget accounts for.
      def overview
        @title = "Budget overview"
        grouped = store.budgets_by_nominal_code
        @rollups = grouped.map { |code, group| ::Reimbursements::NominalCodeRollup.new(code, group) }
        @grand_total = ::Reimbursements::NominalCodeRollup.new(nil, grouped.values.flatten)
        build_area_rollups(grouped.values.flatten)
        unattributed = store.unattributed_actuals
        @unattributed_by_code = unattributed.group_by do |actual|
          actual.nominal_code.presence || ::Reimbursements::DatabaseStore::NO_CODE_LABEL
        end
        # Over the same scoped budgets the cards total, so the summary counts
        # only lines the tables show.
        @over_budget_count = grouped.values.flatten.count(&:over_budget?)
        # A count beside the net, which is debits less credits and can
        # legitimately be negative.
        @unattributed_count = unattributed.size
        @unattributed_total = ::Reimbursements::EusaActual.net(unattributed)
      end

      # One line by hand; a whole year comes in through the budget import.
      def new
        @title = "New budget"
        @people = store.people
        @cost_centres = ::Reimbursements::CostCentre.order(:name).to_a
        @areas = new_budget_areas
      end

      def create
        new_budget = ::Reimbursements::Budget.new(budget_type: "Expense")
        attrs = budget_params(new_budget)
        if (error = budget_validation_error(attrs, new_budget))
          @title = "New budget"
          @people = store.people
          @cost_centres = ::Reimbursements::CostCentre.order(:name).to_a
          @areas = new_budget_areas
          flash.now[:alert] = error
          return render(:new, status: :unprocessable_entity)
        end

        budget = store.create_budget!(attrs.merge(financial_year: selected_financial_year,
                                                  cost_centre: chosen_cost_centre))
        redirect_to edit_admin_reimbursements_budget_path(budget.record_id),
                    notice: "Budget created."
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
      end

      def update
        attrs = budget_params
        if (error = budget_validation_error(attrs))
          return redirect_to(edit_path, alert: error)
        end

        store.update_budget!(@budget.record_id, attrs)
        redirect_to edit_path, notice: "Budget saved."
      end

      # Appends a projected-spend update (amount + date + reason) to this budget;
      # the newest one becomes its current forecast.
      def forecast
        amount = parse_decimal(params[:amount])
        date = parse_date(params[:date])
        if amount.nil? || date.nil?
          return redirect_to(edit_path, alert: "Enter a valid amount and date for the forecast.")
        end

        store.create_forecast!(budget_id: @budget.record_id, amount: amount, date: date,
                               reason: params[:reason].to_s)
        redirect_to edit_path, notice: "Forecast added."
      end

      # Correct a forecast logged in error. Guarded so only a forecast belonging
      # to this budget can be edited through this budget's URL.
      def update_forecast
        return unless forecast_belongs_to_budget?(params[:forecast_id])

        amount = parse_decimal(params[:amount])
        date = parse_date(params[:date])
        if amount.nil? || date.nil?
          return redirect_to(edit_path, alert: "Enter a valid amount and date for the forecast.")
        end

        store.update_forecast!(params[:forecast_id], amount: amount, date: date,
                                                     reason: params[:reason].to_s)
        redirect_to edit_path, notice: "Forecast updated."
      end

      # Remove a forecast logged in error, same ownership guard.
      def delete_forecast
        return unless forecast_belongs_to_budget?(params[:forecast_id])

        store.delete_forecast!(params[:forecast_id])
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

      # A forecast id arriving in the URL must actually belong to this budget —
      # never let one budget's page mutate another budget's forecast log.
      def forecast_belongs_to_budget?(forecast_id)
        return true if store.budget_forecasts(@budget.record_id).any? { |f| f.record_id == forecast_id }

        redirect_to edit_path, alert: "That forecast isn't part of this budget."
        false
      end

      # Finance, or one of the line's owners; anyone else gets a 404.
      def authorize_budget_page!
        @budget = store.find_budget(params[:id])
        raise ActiveRecord::RecordNotFound if @budget.nil? || !budget_page_visible?(@budget)
      end

      def budget_page_visible?(budget)
        return true if can?(:manage, :reimbursements_finance)

        current_person.present? && budget.owner_ids.include?(current_person.record_id)
      end

      def set_budget
        @budget = find_or_404(:find_budget)
      end

      def edit_path
        edit_admin_reimbursements_budget_path(@budget.record_id)
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

      # Every centre's areas for the year: the line's centre is still being
      # chosen on this form, so the browser narrows the list to the one picked
      # (reimbursements-budget-area#costCentreChanged) and area_scope_error
      # refuses a mismatch that gets past it.
      def new_budget_areas
        assignable_areas(year: selected_financial_year)
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
        initial = parse_decimal(params[:initial_budget])
        attrs[:initial_budget] = initial unless initial.nil?
        attrs
      end

      def posted_area_id
        params[:area_id].presence
      end

      # Optional: with one cost centre configured there is nothing to choose,
      # and a budget with no centre still works (the reconcile matcher treats it
      # as belonging to the only one there is). The form's own field wins; the
      # page's ?cost_centre= selector is the fallback, so a budget added while
      # looking at termtime lands in termtime rather than in centre #1.
      def chosen_cost_centre
        ::Reimbursements::CostCentre.find_by(id: params[:cost_centre_id]) ||
          selected_cost_centre || ::Reimbursements::CostCentre.default
      end

      # The same lenient reading as the submitter form: "£1,200" and "12,50" are
      # amounts, not rubbish. A bare BigDecimal() raises on both.
      def parse_decimal(value)
        ::Reimbursements::AmountParser.parse(value)
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
