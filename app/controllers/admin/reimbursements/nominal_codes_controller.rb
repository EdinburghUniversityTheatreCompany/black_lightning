module Admin
  module Reimbursements
    ##
    # Writes to one cost centre's chart of accounts — the codes its budget
    # lines are booked against and the label each one carries. NominalCodeSeed
    # filled the list from the codes the centre's budgets already had, with a
    # label GUESSED from the commonest budget name behind each code;
    # correcting those guesses is what these actions exist for.
    #
    # There is NO index: the list is maintained on the cost centre's own edit
    # page (the spec: "maintained on the cost centre edit page"), so this
    # controller only writes and every response puts the operator back there.
    # It shares that page's `:key` coordinate and finds the centre exactly as
    # SettingsController does.
    #
    # A browser gets a turbo stream replacing the section alone, so adding or
    # retiring a code cannot re-render the cost centre's own form underneath
    # and lose a half-typed mailbox; a plain form post redirects. The notice
    # travels as a toast in the stream, because a redirect's flash is rendered
    # outside the replaced section and would never be seen.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController — the same gate as the Settings page this belongs
    # to. Reads the NominalCode model rather than the store: the store's public
    # API is frozen around expenses, budgets and actuals and knows nothing of
    # this list, which is a settings table rather than portal data.
    class NominalCodesController < FinanceController
      include ListsNominalCodes

      before_action :set_cost_centre

      def create
        nominal_code = ::Reimbursements::NominalCode.new(create_params)
        nominal_code.cost_centre = @cost_centre
        return respond_with_error(nominal_code, prefill: true) unless nominal_code.save

        respond_with_section(message: "#{nominal_code.code} added.")
      end

      def update
        nominal_code = find_nominal_code!
        return respond_with_error(nominal_code) unless nominal_code.update(update_params)

        respond_with_section(message: "#{nominal_code.code} saved.")
      end

      # Retiring beats deleting, and which one happens is decided HERE rather
      # than by the button that was clicked: the row's Retire/Delete label is a
      # prediction made when the page rendered, and a budget line or ledger row
      # booked against the code since then would make it wrong. A code any
      # historical row carries is deactivated — it leaves every picker and
      # stays readable beside the rows already booked against it, the way an
      # absent budget is reported and never deleted.
      def destroy
        nominal_code = find_nominal_code!
        if nominal_code.in_use?
          nominal_code.update!(active: false)
          respond_with_section(message: "#{nominal_code.code} retired. Rows already booked against it " \
                                        "keep their code and its label; nobody can pick it for a new one.")
        else
          nominal_code.destroy!
          respond_with_section(message: "#{nominal_code.code} deleted.")
        end
      end

      private

      def set_cost_centre
        @cost_centre = ::Reimbursements::CostCentre.find_by!(key: params[:key])
      end

      def find_nominal_code!
        ::Reimbursements::NominalCode.where(cost_centre: @cost_centre).find(params[:id])
      end

      # The section as it now stands, plus the message as a toast; or a
      # redirect back to the page holding it when the post came from a browser
      # with no JavaScript. A turbo stream is processed whatever the status, so
      # a refusal keeps its 422.
      def respond_with_section(message:, error: false, new_nominal_code: nil)
        load_nominal_codes(@cost_centre, new_nominal_code: new_nominal_code)
        @toast = { type: error ? "error" : "success", message: message }
        respond_to do |format|
          format.turbo_stream do
            render :respond, status: (error ? :unprocessable_entity : :ok)
          end
          format.html { redirect_to edit_path, **(error ? { alert: message } : { notice: message }) }
        end
      end

      # A refused save re-renders the section. +prefill+ puts the record back
      # in the Add form with the values that were typed — a refused ROW edit
      # must not, or the Add form fills with that row's code and label. The
      # HTML path can only redirect, the page belonging to another controller,
      # so it says what was wrong and the operator retypes the one field.
      def respond_with_error(record, prefill: false)
        respond_with_section(message: record.errors.full_messages.to_sentence, error: true,
                             new_nominal_code: (record if prefill))
      end

      def edit_path
        edit_admin_reimbursements_setting_path(@cost_centre.key, anchor: "nominal_codes")
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
