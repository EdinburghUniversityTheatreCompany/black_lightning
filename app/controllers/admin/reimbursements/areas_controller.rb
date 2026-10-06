module Admin
  module Reimbursements
    ##
    # Finance management of Areas, the show or project a group of budget lines
    # belongs to. An area holds the agreed total and the owners; its budgets are
    # edited inline as nested fields.
    #
    # Model-backed (assigns onto @area and save!s), so the form is simple_form_for
    # and nests under params[:reimbursements_area].
    class AreasController < FinanceController
      include ListsClaims

      # Budget owners lack the finance permission, so #show swaps FinanceController's
      # gate for the union in #authorize_area_page!.
      skip_before_action :authorize_finance!, only: %i[show]
      before_action :authorize_area_page!, only: %i[show]
      before_action :set_area, only: %i[edit update]

      # Only what _budget_fields renders: to_unsafe_h would let a raw "£1,200"
      # store as 0 and a posted cost_centre_id/financial_year_id move the line.
      BUDGET_ROW_FIELDS = %i[id name nominal_code area_id budget_type initial_budget].freeze

      def index
        @title = "Areas"
        @areas = paginate(store.areas_for_year)
        @people_by_id = store.people.index_by(&:record_id)
      end

      # Read-only for an owner; finance gets the same page with the actions and
      # the finance vocabulary beside each plain label.
      def show
        @title = @area.name
        @summary = ::Reimbursements::SpendSummary.for_area(@area)
        @expense_lines, @income_lines = @area.budgets.partition { |line| !line.income? }
        load_claims(@area.budgets)
        @changes = ::Reimbursements::BudgetChanges.for_area(@area)
      end

      def new
        @area = ::Reimbursements::Area.new
        render_form(:new, [])
      end

      def create
        attrs = area_params
        if (error = validation_error(attrs))
          @area = ::Reimbursements::Area.new(attrs)
          return render_form(:new, posted_owner_ids, error: error)
        end

        area = store.create_area!(attrs.merge(financial_year: selected_financial_year,
                                              cost_centre: chosen_cost_centre))
        store.sync_area_owners!(area.record_id, posted_owner_ids)
        redirect_to edit_admin_reimbursements_area_path(area.record_id), notice: "Area created."
      end

      def edit = render_form(:edit, @area.owner_ids)

      def update
        attrs = area_params
        if (error = validation_error(attrs))
          return render_form(:edit, posted_owner_ids, error: error)
        end

        @area.assign_attributes(attrs)
        @area.budgets_attributes = permitted_budgets_attributes if permitted_budgets_attributes
        @area.save!
        store.sync_area_owners!(@area.record_id, posted_owner_ids)
        redirect_to edit_admin_reimbursements_area_path(@area.record_id), notice: "Area saved."
      end

      private

      def render_form(action, owner_ids, error: nil)
        @title = action == :new ? "New area" : "Area: #{@area.name}"
        @people = store.people
        @owner_ids = owner_ids
        flash.now[:alert] = error if error
        render action, status: error ? :unprocessable_entity : :ok
      end

      def posted_owner_ids = Array(area_form_params[:owner_ids]).compact_blank

      # Finance, or a person the area's owners name. Anyone else gets a 404, not
      # a 403, which would tell a stranger the area exists.
      def authorize_area_page!
        @area = store.find_area(params[:id])
        raise ActiveRecord::RecordNotFound if @area.nil? || !area_page_visible?(@area)
      end

      def area_page_visible?(area)
        return true if can?(:manage, :reimbursements_finance)

        current_person.present? && area.owner_ids.include?(current_person.record_id)
      end

      def set_area
        @area = find_or_404(:find_area)
      end

      def area_form_params = params.require(:reimbursements_area)

      # The parsed BigDecimal, never the raw param: AR's to_d would store "£1,200" as 0.
      def area_params
        source = area_form_params
        attrs = {
          name: source[:name].to_s.strip,
          initial_budget: ::Reimbursements::AmountParser.parse(source[:initial_budget]),
          notes: source[:notes].to_s
        }
        # cast(nil) is nil, and assigning it would NULL a NOT NULL column, so an
        # absent param leaves the key out.
        active = ActiveModel::Type::Boolean.new.cast(source[:active])
        attrs[:active] = active unless active.nil?
        # A junk value is left out too: the inclusion validation would 500 save!.
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

      # The nested rows with each typed amount parsed. A blank figure drops the
      # key: nil or £0 would stand for a plan nobody set (PlannedAmount), and
      # dropping it leaves an existing line's figure alone. Memoised so the
      # validation and the write read the same parsed rows.
      def permitted_budgets_attributes
        @permitted_budgets_attributes ||=
          area_form_params.permit(budgets_attributes: BUDGET_ROW_FIELDS)[:budgets_attributes]
                          &.each_value { |row| normalise_initial_budget(row) }
      end

      # An unreadable value stays raw for #budget_row_value_error to report
      # before anything is written.
      def normalise_initial_budget(row)
        return unless row.key?("initial_budget")

        raw = row["initial_budget"]
        if raw.blank?
          row.delete("initial_budget")
        elsif (parsed = ::Reimbursements::AmountParser.parse(raw))
          row["initial_budget"] = parsed
        end
      end

      # Budget validates only its name, so what a row may leave blank is decided here.
      def budget_rows_error
        rows = permitted_budgets_attributes
        return nil if rows.blank?

        rows.each_value.filter_map { |row| budget_row_error(row) || budget_row_value_error(row) }.first
      end

      # A NEW line needs a name and a nominal code. An EXISTING row is checked
      # only for its name: the form posts every child row, so requiring a code
      # would lock an area holding a code-less line (supported state) out of its
      # own form, Detach included. A blank name would raise in save!, but a row
      # posted with no name key at all (detach-only) is not a blank name.
      def budget_row_error(row)
        if row[:id].present?
          return row.key?(:name) && row[:name].blank? ? "A budget line's name can't be blank." : nil
        end
        return nil if ::Reimbursements::Area::UNTOUCHED_BUDGET_ROW.call(row)
        return nil if row[:name].present? && row[:nominal_code].present?

        "A new budget line needs a name and a nominal code."
      end

      # An unreadable amount is silent wrong money, so it blocks the whole save.
      def budget_row_value_error(row)
        if row["initial_budget"].present? && !row["initial_budget"].is_a?(BigDecimal)
          return "#{row['initial_budget'].to_s.strip.inspect} isn't an amount. Use a number " \
                 "like 1200 or £1,200, or leave it blank."
        end
        return nil if row["budget_type"].blank?
        return nil if ::Reimbursements::Budget::TYPES.include?(row["budget_type"])

        "Choose a valid budget type for each line."
      end

      # The form field wins, then the ?cost_centre= selector, so an area added
      # while viewing termtime does not land in centre #1.
      def chosen_cost_centre
        ::Reimbursements::CostCentre.find_by(id: area_form_params[:cost_centre_id]) ||
          selected_cost_centre || ::Reimbursements::CostCentre.default
      end
    end
  end
end
