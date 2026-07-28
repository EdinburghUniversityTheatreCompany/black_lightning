module Admin
  module Reimbursements
    ##
    # Financial years — the pot-per-year the budget screens scope to. Each
    # Fringe recurs with its own budgets, expenses and actuals, so setting the
    # next one up is: create the year, import its budgets, check them, then
    # switch to it.
    #
    # The switch is #activate, deliberately its own action rather than a
    # checkbox on the edit form. Activating changes what every submitter sees in
    # their budget picker, so it must be a decision someone takes on purpose —
    # which is also why +active+ is not a permitted parameter here.
    #
    # The +key+ is the URL slug and is settable only at creation, mirroring
    # SettingsController's handling of a cost centre's key: it appears in links
    # and bookmarks, so quietly changing it on an edit would break them.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class FinancialYearsController < FinanceController
      before_action :set_financial_year, only: %i[edit update activate]

      def index
        @title = "Financial years"
        @financial_years = ::Reimbursements::FinancialYear.recent_first.to_a
      end

      def new
        @title = "New financial year"
        @financial_year = ::Reimbursements::FinancialYear.new
      end

      def create
        @financial_year = ::Reimbursements::FinancialYear.new(create_params)
        if @financial_year.save
          redirect_to edit_path(@financial_year),
                      notice: "#{@financial_year.label} created. Import its budgets below, then make " \
                              "it the active year when you're ready."
        else
          @title = "New financial year"
          flash.now[:alert] = @financial_year.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @title = "Financial year: #{@financial_year.label}"
      end

      def update
        if @financial_year.update(update_params)
          redirect_to edit_path(@financial_year), notice: "#{@financial_year.label} saved."
        else
          @title = "Financial year: #{@financial_year.label}"
          flash.now[:alert] = @financial_year.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_entity
        end
      end

      # Make this the year submitters file against. FinancialYear#activate!
      # moves the flag off the incumbent in one transaction.
      def activate
        @financial_year.activate!
        redirect_to admin_reimbursements_financial_years_path,
                    notice: "#{@financial_year.label} is now the active financial year."
      rescue ActiveRecord::RecordInvalid => e
        redirect_to admin_reimbursements_financial_years_path,
                    alert: "Could not activate #{@financial_year.label}: #{e.record.errors.full_messages.to_sentence}"
      end

      private

      def set_financial_year
        @financial_year = ::Reimbursements::FinancialYear.find_by!(key: params[:key])
      end

      def edit_path(year)
        edit_admin_reimbursements_financial_year_path(year.key)
      end

      # +key+ is accepted at creation (the collapsed Advanced field) and derived
      # from the label when left blank.
      def create_params
        params.require(:financial_year).permit(:label, :key, :starts_on, :ends_on)
      end

      def update_params
        params.require(:financial_year).permit(:label, :starts_on, :ends_on)
      end
    end
  end
end
