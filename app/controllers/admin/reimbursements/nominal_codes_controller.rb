module Admin
  module Reimbursements
    ##
    # One cost centre's chart of accounts, maintained by that centre's finance
    # admin: the codes its budget lines are booked against and the label each
    # one carries. NominalCodeSeed filled the list from the codes the centre's
    # budgets already had, with a label GUESSED from the commonest budget name
    # behind each code — correcting those guesses is what this screen is for.
    #
    # Reached from the cost centre's own Settings page and sharing its
    # coordinate (`settings/:key/nominal_codes`, the centre found by +key+ as
    # SettingsController finds it), because the list belongs to the centre and
    # nothing else selects it.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController — the same gate as the Settings page this hangs
    # off. Reads the NominalCode model rather than the store: the store's
    # public API is frozen around expenses, budgets and actuals and knows
    # nothing of this list, which is a settings table rather than portal data.
    class NominalCodesController < FinanceController
      before_action :set_cost_centre

      def index
        @title = "Nominal codes: #{@cost_centre.name}"
        load_codes
      end

      def create
        # The add form's own record, held apart from the rows: a refused save
        # re-renders this page, and the two typed fields must come back with it.
        @new_nominal_code = ::Reimbursements::NominalCode.new(create_params)
        @new_nominal_code.cost_centre = @cost_centre
        return render_index_with_error(@new_nominal_code) unless @new_nominal_code.save

        redirect_to index_path, notice: "#{@new_nominal_code.code} added."
      end

      def update
        nominal_code = find_nominal_code!
        return render_index_with_error(nominal_code) unless nominal_code.update(update_params)

        redirect_to index_path, notice: "#{nominal_code.code} saved."
      end

      # Retiring beats deleting, and which one happens is decided HERE rather
      # than by the button that was clicked: the row's Retire/Delete label is a
      # prediction made when the page rendered, and a budget line charged to
      # the code since then would make it wrong. A code a budget carries is
      # deactivated — it leaves every picker and stays readable beside the
      # lines already booked against it, the way an absent budget is reported
      # and never deleted.
      def destroy
        nominal_code = find_nominal_code!
        if nominal_code.in_use?
          nominal_code.update!(active: false)
          redirect_to index_path, notice: "#{nominal_code.code} retired. Budget lines already booked " \
                                          "against it keep their code and its label; nobody can pick " \
                                          "it for a new one."
        else
          nominal_code.destroy!
          redirect_to index_path, notice: "#{nominal_code.code} deleted."
        end
      end

      private

      def set_cost_centre
        @cost_centre = ::Reimbursements::CostCentre.find_by!(key: params[:key])
      end

      def find_nominal_code!
        ::Reimbursements::NominalCode.where(cost_centre: @cost_centre).find(params[:id])
      end

      def load_codes
        @new_nominal_code ||= ::Reimbursements::NominalCode.new
        @nominal_codes = ::Reimbursements::NominalCode.for_cost_centre(@cost_centre).to_a
        @budget_counts = ::Reimbursements::NominalCode.budget_counts(@cost_centre,
                                                                     @nominal_codes.map(&:code))
      end

      def index_path
        admin_reimbursements_nominal_codes_path(@cost_centre.key)
      end

      # The add form and every row's form sit on this one page, so a refused
      # save re-renders it rather than redirecting, which would lose whatever
      # the operator had typed into the add form.
      def render_index_with_error(record)
        @title = "Nominal codes: #{@cost_centre.name}"
        load_codes
        flash.now[:alert] = record.errors.full_messages.to_sentence
        render :index, status: :unprocessable_entity
      end

      def create_params
        params.permit(:code, :label)
      end

      # +code+ is deliberately NOT updatable. It is the join to every budget
      # line, actuals row and export booked against this account, all of which
      # store the code as a string rather than a link, so rewriting it here
      # would leave every one of them labelled by an account that no longer
      # exists. A code typed wrong is deleted (nothing carries it yet) and
      # added again.
      def update_params
        params.permit(:label, :active)
      end
    end
  end
end
