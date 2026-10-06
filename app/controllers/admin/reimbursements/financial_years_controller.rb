module Admin
  module Reimbursements
    ##
    # Financial years, the pot-per-year the budget screens scope to: create the next year,
    # import its budgets, check them, then switch to it.
    #
    # Activation is its own action, so +active+ is not a permitted param: it changes every
    # submitter's budget picker and must be a deliberate decision. +key+ is settable only at
    # creation, because links and bookmarks carry it.
    #
    # Gated by `:manage, :reimbursements_finance` via FinanceController.
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

      def create_params
        params.require(:financial_year).permit(:label, :key, :starts_on, :ends_on)
      end

      def update_params
        params.require(:financial_year).permit(:label, :starts_on, :ends_on)
      end
    end
  end
end
