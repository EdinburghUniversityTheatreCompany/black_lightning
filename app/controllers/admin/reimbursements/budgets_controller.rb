module Admin
  module Reimbursements
    ##
    # Finance-team management of the budgets: an overview of every
    # budget's financials (initial, rolled-up current forecast, committed, total
    # paid, remaining, variance), an edit form for the operator-editable fields
    # (name, nominal code, visible-to-submitters, notes, initial budget, budget
    # type and the many-to-many People owners), and a forecast-history log with
    # an "add a projected-spend update" action that appends a Budget Forecasts
    # record.
    #
    # The rollups (current_forecast, committed_amount, total_paid, remaining,
    # variance) are read-only displays — Budget derives them from the claims.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class BudgetsController < FinanceController
      before_action :set_budget, only: %i[edit update forecast update_forecast delete_forecast]

      def index
        @title = "Reimbursements Budgets"
        # This table (and its CSV) shows the EUSA-actual rollup per line, so it's
        # one of the two readers that pays for the actuals preload.
        sorted = store.budgets_with_actuals.sort_by { |budget| budget.name.to_s.downcase }
        @people_by_id = store.people.index_by(&:record_id)
        # The unscoped, fully-preloaded id->Area lookup (owners, and each
        # area's budgets' expenses/forecasts) — the grouped index reads every
        # area figure off THESE objects, never off budget.area, or each
        # area's committed_amount/allocated would N+1 across its budgets'
        # expenses and forecasts.
        @areas_by_id = store.areas.index_by(&:record_id)
        respond_to do |format|
          format.html { @budgets = paginate(sorted) }
          format.csv { send_export ::Reimbursements::Exports::Budgets, sorted }
        end
      end

      # A finance overview of the same budgets down two axes — EUSA's nominal
      # code and Bedlam's areas — each with a subtotal per group and per budget
      # type, plus a separate list of the EUSA ledger rows no budget's figures
      # account for.
      def overview
        @title = "Budget overview"
        grouped = store.budgets_by_nominal_code
        @rollups = grouped.map { |code, group| ::Reimbursements::NominalCodeRollup.new(code, group) }
        @grand_total = ::Reimbursements::NominalCodeRollup.new(nil, grouped.values.flatten)
        build_area_rollups(grouped.values.flatten)
        @unattributed_by_code = store.unattributed_actuals.group_by do |actual|
          actual.nominal_code.presence || ::Reimbursements::DatabaseStore::NO_CODE_LABEL
        end
      end

      # One budget line by hand. The spreadsheet import is the way a year gets
      # set up; this is for the single line that turns up mid-year and isn't
      # worth a re-import.
      def new
        @title = "New budget"
        @people = store.people
        @cost_centres = ::Reimbursements::CostCentre.order(:name).to_a
        @areas = store.areas_for_year
      end

      def create
        attrs = budget_params(::Reimbursements::Budget.new(budget_type: "Expense"))
        if (error = budget_validation_error(attrs))
          @title = "New budget"
          @people = store.people
          @cost_centres = ::Reimbursements::CostCentre.order(:name).to_a
          @areas = store.areas_for_year
          flash.now[:alert] = error
          return render(:new, status: :unprocessable_entity)
        end

        budget = store.create_budget!(attrs.merge(financial_year: selected_financial_year,
                                                  cost_centre: chosen_cost_centre))
        redirect_to edit_admin_reimbursements_budget_path(budget.record_id),
                    notice: "Budget created."
      end

      def edit
        @title = "Budget: #{@budget.name}"
        @people = store.people
        # The budget's OWN area is always offered, however the page is scoped.
        # areas_for_year is year- and cost-centre-scoped while area_id writes
        # unscoped ("" detaches), so an area outside the rendered set left the
        # select reading "— none —" and any Save — one changing only the
        # notes — nilled a link nobody touched.
        @areas = (store.areas_for_year + [ @budget.area ]).compact.uniq
        @forecasts = store.budget_forecasts(@budget.record_id)
        # URL-as-state: ?edit_forecast=<id> renders that one row as an inline
        # edit form (no JS), so a mistyped forecast can be corrected in place.
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

      # The overview's second axis: the SAME budgets the nominal-code card
      # totals, regrouped under their area, so the two cards can never quote
      # different money for one page. Each area object comes from store.areas —
      # unscoped and fully preloaded, the reader every area figure has to be
      # read off, never budget.area, whose own #budgets collection is unloaded
      # and would N+1 across its expenses and forecasts.
      def build_area_rollups(budgets)
        areas_by_id = store.areas.index_by(&:record_id)
        by_area_id = budgets.group_by { |budget| budget.area&.record_id }
        unassigned = by_area_id.delete(nil)
        @area_rollups = by_area_id
                        .map { |id, group| ::Reimbursements::AreaRollup.new(area: areas_by_id[id], budgets: group) }
                        .sort_by { |rollup| rollup.name.to_s.downcase }
        # Nil rather than an empty rollup, so the view renders no "Not in an
        # area" heading on a portal whose lines all sit in one.
        @unassigned_rollup = unassigned && ::Reimbursements::AreaRollup.new(area: nil, budgets: unassigned)
      end

      # A forecast id arriving in the URL must actually belong to this budget —
      # never let one budget's page mutate another budget's forecast log.
      def forecast_belongs_to_budget?(forecast_id)
        return true if store.budget_forecasts(@budget.record_id).any? { |f| f.record_id == forecast_id }

        redirect_to edit_path, alert: "That forecast isn't part of this budget."
        false
      end

      def set_budget
        @budget = find_or_404(:find_budget)
      end

      def edit_path
        edit_admin_reimbursements_budget_path(@budget.record_id)
      end

      # The budget write path has no model-backed form object, so a blank
      # name/nominal code or a mangled budget_type param has to be caught here
      # or it reaches the store with no feedback to the operator.
      def budget_validation_error(attrs)
        return "Enter a budget name." if attrs[:name].blank?
        return "Enter a nominal code." if attrs[:nominal_code].blank?
        unless ::Reimbursements::Budget::TYPES.include?(attrs[:budget_type])
          return "Choose a valid budget type."
        end

        owner_ids_error(attrs[:owner_ids])
      end

      # Operator-editable budget attributes. Rollups/formulas are never written.
      # +active+ (visible-to-submitters) comes from a checkbox, so absence means
      # "off". +initial_budget+ is only sent when a valid number is given, so a
      # blank field can't zero it.
      def budget_params(budget = @budget)
        attrs = {
          name: params[:name].to_s.strip,
          nominal_code: params[:nominal_code].to_s.strip,
          notes: params[:notes].to_s,
          budget_type: params[:budget_type].presence || budget.budget_type,
          active: params[:active].present?
        }
        # A form that renders the picker always posts it, so an ABSENT param is
        # a caller that never offered the field — "no change", the same guard
        # budget_type has. A posted "" is still the deliberate detach the
        # select's "— none —" option means.
        attrs[:area_id] = params[:area_id].presence if params.key?(:area_id)
        # Ownership is edited on the AREA, so an area-bound budget's form shows
        # its inherited owners read-only and NOTHING it posts may be written:
        # Budget#owner_ids reads the area's owners while sync_owner_ids! writes
        # the budget's own rows, so a Save that carried the area's list would
        # delete the own-owner rows the backfill kept in order to be
        # reversible, and an ownerless area's empty list would delete them all
        # (where.not(person_id: []) compiles to WHERE 1=1). Omitting the KEY,
        # not sending [], is what stops update_budget! syncing at all.
        unless budget.area_id
          attrs[:owner_ids] = Array(params[:owner_ids]).reject(&:blank?)
        end
        initial = parse_decimal(params[:initial_budget])
        attrs[:initial_budget] = initial unless initial.nil?
        attrs
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
