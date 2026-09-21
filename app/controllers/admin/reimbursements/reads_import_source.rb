module Admin
  module Reimbursements
    ##
    # The "paste it, or upload the .xlsx" half of a stateless import wizard —
    # the controller side of `shared/form/paste_or_upload`, shared by the budget
    # import and the expense import so the two cannot drift about which input
    # wins or what an empty submit does.
    #
    # A file on THIS request beats the text box, because the preview carries an
    # upload on as canonical TSV in a hidden field and apply therefore only ever
    # sees text — an upload never has a second file to re-send.
    #
    # The includer supplies NOTHING_PASTED_ALERT, since it names what the
    # operator was meant to paste.
    module ReadsImportSource
      extend ActiveSupport::Concern

      included do
        # The views draw their cost-centre select from it, so a prefilled or
        # sole centre arrives selected and everything else shows the prompt.
        helper_method :chosen_cost_centre
      end

      private

      def import_source
        uploaded_file || params[:pasted_text].to_s
      end

      # :canonical_tsv is this wizard's OWN #to_tsv output coming back from the
      # preview's hidden field — the only input whose cells carry escape
      # sequences. A wizard that renders the `canonical` marker opts in; one
      # that does not keeps reading everything as :paste.
      def input_type
        return :xlsx if uploaded_file
        return :canonical_tsv if params[:canonical].present?

        :paste
      end

      # params[:file] is a String on a form submitted with the picker left
      # empty, which answers neither #path nor #read.
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

      # A whole committee spreadsheet, or a whole sheet of settled claims,
      # landing in the wrong pot is a large quiet mistake, and the wizards used
      # to PRESELECT `selectable_cost_centres.first` — while everywhere else in
      # this portal "none" means "every centre" as a stated safety rule.
      #
      # So the operator has to say, and this is where they are made to. It
      # matters only where there is something to choose: with one centre
      # configured, `#chosen_cost_centre` below answers it and nothing is asked.
      #
      # Shared by both wizards rather than written twice, so they cannot drift
      # about when a centre is demanded (and jscpd gates duplication at 0).
      def cost_centre_chosen?
        return true if chosen_cost_centre

        flash.now[:alert] = self.class::NO_COST_CENTRE_CHOSEN_ALERT
        false
      end

      # The centre this import lands in: the one the URL or the form named, or
      # the sole configured one, where there is genuinely nothing to choose
      # between. Never `.first` of several — see CostCentre.default's note on
      # why naming an arbitrary pot is the bug this replaced.
      def chosen_cost_centre
        return selected_cost_centre if selected_cost_centre

        selectable_cost_centres.one? ? selectable_cost_centres.first : nil
      end
    end
  end
end
