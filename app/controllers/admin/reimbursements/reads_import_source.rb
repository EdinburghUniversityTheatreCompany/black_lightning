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

      private

      def import_source
        uploaded_file || params[:pasted_text].to_s
      end

      def input_type = uploaded_file ? :xlsx : :paste

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
    end
  end
end
