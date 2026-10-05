module Admin
  module Reimbursements
    ##
    # The paste-or-upload half of a stateless import wizard, shared by the
    # budget and expense imports. A file on THIS request beats the text box:
    # apply only ever sees the preview's canonical TSV.
    #
    # The includer supplies NOTHING_PASTED_ALERT and NO_COST_CENTRE_CHOSEN_ALERT,
    # since they name what the operator was meant to paste and choose.
    module ReadsImportSource
      extend ActiveSupport::Concern

      included do
        # The views draw their cost-centre select from it.
        helper_method :chosen_cost_centre
      end

      private

      def import_source
        uploaded_file || params[:pasted_text].to_s
      end

      # A wizard that renders the `canonical` marker opts in to unescaping its
      # own #to_tsv output; one that does not reads everything as :paste.
      def input_type
        return :xlsx if uploaded_file
        return :canonical_tsv if params[:canonical].present?

        :paste
      end

      # params[:file] is a String when the picker is left empty.
      def uploaded_file
        file = params[:file]
        file.respond_to?(:path) ? file : nil
      end

      def source_present?
        return true if uploaded_file
        return true if params[:pasted_text].to_s.strip.present?

        flash.now[:alert] = self.class::NOTHING_PASTED_ALERT
        false
      end

      # A whole sheet in the wrong pot is a large quiet mistake, so with several
      # centres the operator must choose: never preselect `.first`.
      def cost_centre_chosen?
        return true if chosen_cost_centre

        flash.now[:alert] = self.class::NO_COST_CENTRE_CHOSEN_ALERT
        false
      end

      # The centre the URL or form named, or the sole configured one.
      def chosen_cost_centre
        return selected_cost_centre if selected_cost_centre

        selectable_cost_centres.one? ? selectable_cost_centres.first : nil
      end
    end
  end
end
