module Admin
  module Reimbursements
    ##
    # The paste-or-upload half of a stateless import wizard, shared by the
    # budget and expense imports, with the show, preview and template steps
    # they do identically. A file on THIS request beats the text box: apply
    # only ever sees the preview's canonical TSV.
    #
    # The includer supplies the alerts NOTHING_PASTED_ALERT,
    # NO_COST_CENTRE_CHOSEN_ALERT, NO_FINANCIAL_YEAR_ALERT and NO_COST_CENTRE_ALERT
    # (they name what the operator was meant to paste, choose or add), plus
    # #import_class, #build_import (sets @import) and #import_path, and its own
    # #apply.
    module ReadsImportSource
      extend ActiveSupport::Concern

      included do
        # The views draw their cost-centre select from it.
        helper_method :chosen_cost_centre
      end

      # Flags a portal with no years or centres before anything is pasted.
      def show
        destination_available?
      end

      def preview
        return render(:show) unless source_present?
        return render(:show, status: :unprocessable_entity) unless destination_chosen?

        build_import
        render :preview
      end

      # The columns the importer reads plus a hint row, which it skips.
      def template
        send_data import_class::TSV_HEADERS.to_csv + import_class::TEMPLATE_HINTS.to_csv,
                  type: "text/csv",
                  filename: "#{import_class.name.demodulize.underscore.dasherize}-template.csv"
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

      # Somewhere to import INTO, and a centre the operator chose (or the only one).
      # Each check flashes its own alert, so the first failure is the one shown.
      def destination_chosen?
        destination_available? && cost_centre_chosen?
      end

      # Whether there is anything to import INTO. Distinct from no centre picked
      # yet (#cost_centre_chosen?): this is a portal with no years or centres.
      def destination_available?
        if selected_financial_year.nil?
          flash.now[:alert] = self.class::NO_FINANCIAL_YEAR_ALERT
        elsif selectable_cost_centres.empty?
          flash.now[:alert] = self.class::NO_COST_CENTRE_ALERT
        else
          return true
        end

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

      # Re-rendered rather than redirected, so a forty-line paste survives.
      def render_blocked_preview(alert = "Nothing was imported. Fix the lines flagged below and try again.")
        flash.now[:alert] = alert
        render :preview, status: :unprocessable_entity
      end
    end
  end
end
