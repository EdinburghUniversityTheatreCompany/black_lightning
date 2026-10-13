module Admin
  module Reimbursements
    ##
    # Writes to a cost centre's nominal codes, which are listed on its Settings
    # edit page (so no index). A browser gets a turbo stream replacing that
    # section alone, so a half-typed mailbox in the centre's own form survives.
    # Reads NominalCode directly: it is a settings table the store does not cover.
    class NominalCodesController < FinanceController
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

      # Retiring beats deleting, decided here rather than by the button, whose
      # label was a prediction made when the page rendered.
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

      # A turbo stream is processed whatever the status, so a refusal keeps its 422.
      def respond_with_section(message:, error: false, new_nominal_code: nil)
        @new_nominal_code = new_nominal_code
        @toast = { type: error ? "error" : "success", message: message }
        respond_to do |format|
          format.turbo_stream do
            render :respond, status: (error ? :unprocessable_entity : :ok)
          end
          format.html { redirect_to edit_path, **(error ? { alert: message } : { notice: message }) }
        end
      end

      # +prefill+ puts a refused ADD's typed values back in the Add form; a
      # refused row edit must not, or the Add form fills with that row.
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

      # +code+ is not updatable: budgets, actuals and exports store it as a
      # string, so a rename strands them. A mistyped code is deleted and re-added.
      def update_params
        params.permit(:label, :active)
      end
    end
  end
end
