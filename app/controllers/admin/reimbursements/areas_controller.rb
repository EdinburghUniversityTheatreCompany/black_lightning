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
        budgets_attrs = area_form_params[:budgets_attributes]
        @area.budgets_attributes = budgets_attrs.to_unsafe_h if budgets_attrs
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
        attrs
      end

      def validation_error(attrs)
        return "Enter a name." if attrs[:name].blank?
        return "That budget figure isn't a number I can read." if
          area_form_params[:initial_budget].present? && attrs[:initial_budget].nil?

        owner_ids_error(area_form_params[:owner_ids])
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
