module Admin
  module Reimbursements
    ##
    # Finance-team management of Areas: the show/project/heading a group of
    # budget lines belongs to. An area holds the agreed total and the owners;
    # its budgets are edited inline here as nested fields (see Area's
    # accepts_nested_attributes_for :budgets). Gated by the finance grid
    # permission (`:manage, :reimbursements_finance`) via FinanceController.
    #
    # Area is genuinely model-backed (the update action assigns straight onto
    # @area and calls save!, unlike Budget's store-mediated writes), so the
    # form is simple_form_for rather than the flat-param form_with convention
    # — and its fields arrive nested under params[:reimbursements_area].
    # #area_form_params reads that nested hash when present, falling back to
    # the bare top-level params otherwise, so a params hash posted directly
    # (as a controller test does) works exactly like a real form submission.
    class AreasController < FinanceController
      before_action :set_area, only: %i[edit update]

      # Only the fields areas/_budget_fields.html.erb actually renders.
      # to_unsafe_h would accept any Budget column: a raw-string
      # initial_budget would be cast by AR with to_d and store a "£1,200" as
      # 0, and a posted cost_centre_id/financial_year_id could move the line
      # into another pot or year.
      BUDGET_ROW_FIELDS = %i[id name nominal_code area_id].freeze

      # GET /admin/reimbursements/areas
      def index
        @title = "Areas"
        @areas = paginate(store.areas_for_year)
        @people_by_id = store.people.index_by(&:record_id)
      end

      # GET /admin/reimbursements/areas/new
      def new
        @title = "New area"
        @area = ::Reimbursements::Area.new
        @people = store.people
        @cost_centres = ::Reimbursements::CostCentre.order(:name).to_a
        @owner_ids = []
      end

      # POST /admin/reimbursements/areas
      def create
        attrs = area_params
        if (error = validation_error(attrs))
          @title = "New area"
          @area = ::Reimbursements::Area.new(attrs)
          @people = store.people
          @cost_centres = ::Reimbursements::CostCentre.order(:name).to_a
          @owner_ids = Array(area_form_params[:owner_ids])
          flash.now[:alert] = error
          return render(:new, status: :unprocessable_entity)
        end

        area = store.create_area!(attrs.merge(financial_year: selected_financial_year,
                                              cost_centre: chosen_cost_centre))
        store.sync_area_owners!(area.record_id, Array(area_form_params[:owner_ids]).compact_blank)
        redirect_to edit_admin_reimbursements_area_path(area.record_id), notice: "Area created."
      end

      # GET /admin/reimbursements/areas/:id/edit
      def edit
        @title = "Area: #{@area.name}"
        @people = store.people
        @owner_ids = @area.owner_ids
      end

      # PATCH /admin/reimbursements/areas/:id
      def update
        attrs = area_params
        if (error = validation_error(attrs))
          @title = "Area: #{@area.name}"
          @people = store.people
          @owner_ids = Array(area_form_params[:owner_ids])
          flash.now[:alert] = error
          return render(:edit, status: :unprocessable_entity)
        end

        @area.assign_attributes(attrs)
        budgets_attrs = permitted_budgets_attributes
        @area.budgets_attributes = budgets_attrs if budgets_attrs
        @area.save!
        store.sync_area_owners!(@area.record_id, Array(area_form_params[:owner_ids]).compact_blank)
        redirect_to edit_admin_reimbursements_area_path(@area.record_id), notice: "Area saved."
      end

      private

      def set_area
        @area = find_or_404(:find_area)
      end

      # simple_form_for @area nests every field under
      # params[:reimbursements_area] (Area's model_name.param_key), a real
      # browser submission always does. A controller test posting a flat
      # params hash carries no such key, so this falls back to the bare
      # params — the two shapes read identically from here down.
      def area_form_params
        nested = params[:reimbursements_area]
        nested.present? ? nested : params
      end

      # The PARSED BigDecimal, never the raw param: AR casts a String to a
      # decimal column with to_d, so a typed "£1,200" would store as 0.
      def area_params
        source = area_form_params
        attrs = {
          name: source[:name].to_s.strip,
          initial_budget: ::Reimbursements::AmountParser.parse(source[:initial_budget]),
          notes: source[:notes].to_s
        }
        # Only written when the param is genuinely present. simple_form's
        # boolean widget always posts "0" or "1" (its hidden-field fallback),
        # so a real submission never hits the nil branch — but
        # ActiveModel::Type::Boolean.new.cast(nil) is nil, not false, and
        # assigning nil would try to NULL a NOT NULL column and raise on
        # save. Leaving the key out entirely keeps the current value.
        active = ActiveModel::Type::Boolean.new.cast(source[:active])
        attrs[:active] = active unless active.nil?
        # Only ever one of the two the radio pair offers. Anything else is left
        # out, keeping the current value, exactly as :active is above: Area
        # validates the inclusion, so a junk value reaching save! would raise
        # and 500 the form rather than report anything an operator can act on.
        basis = source[:budget_basis].to_s
        attrs[:budget_basis] = basis if ::Reimbursements::Area::BASES.include?(basis)
        attrs
      end

      def validation_error(attrs)
        return "Enter a name." if attrs[:name].blank?
        return "That budget figure isn't a number I can read." if
          area_form_params[:initial_budget].present? && attrs[:initial_budget].nil?

        owner_ids_error(area_form_params[:owner_ids]) || budget_rows_error
      end

      # The nested budget rows, filtered to the fields the form renders.
      def permitted_budgets_attributes
        source = area_form_params
        return nil if source[:budgets_attributes].blank?

        source.permit(budgets_attributes: BUDGET_ROW_FIELDS)[:budgets_attributes]
      end

      # Budget itself validates only the name, so what a budget row may leave
      # blank is decided here. A row posting neither field is absent rather
      # than incomplete (a detach-only params hash).
      def budget_rows_error
        rows = permitted_budgets_attributes
        return nil if rows.blank?

        rows.each_value.filter_map { |row| budget_row_error(row) }.first
      end

      # A NEW line typed here needs both fields, the intent
      # BudgetsController#budget_validation_error has for a budget's own form.
      # An EXISTING child is checked only for its NAME, and the difference
      # matters: this form posts EVERY child row, not just the one being
      # edited, so requiring a nominal code of all of them locks an area
      # holding one code-less line out of its own form entirely — its name,
      # agreed total, owners and notes, AND the "Detach from this area"
      # control that would remove the offending line. A blank code is
      # supported state (BudgetImport#missing_nominal_codes allows it and the
      # overview has a "(none)" bucket for it), so that is reachable with
      # ordinary data. A blank NAME never is: Budget validates it, so letting
      # one through reaches save!, which raises and 500s the form instead of
      # reporting anything the operator can act on.
      def budget_row_error(row)
        return nil unless row.key?("name") || row.key?("nominal_code")

        if row[:id].present?
          return "A budget line's name can't be blank." if row[:name].blank?

          return nil
        end
        # Both blank on a new row is the untouched "Add" template row, which
        # reject_if: :all_blank drops.
        return nil if row[:name].blank? && row[:nominal_code].blank?
        return nil if row[:name].present? && row[:nominal_code].present?

        "A new budget line needs a name and a nominal code."
      end

      # Optional: with one cost centre configured there is nothing to choose,
      # and an area with no centre still works (same leniency as a budget's).
      # The form's own field wins; the page's ?cost_centre= selector is the
      # fallback, so an area added while looking at termtime lands in
      # termtime rather than in centre #1.
      def chosen_cost_centre
        ::Reimbursements::CostCentre.find_by(id: area_form_params[:cost_centre_id]) ||
          selected_cost_centre || ::Reimbursements::CostCentre.default
      end
    end
  end
end
