module Admin
  module Reimbursements
    ##
    # Per-cost-centre operational settings, porting bedlam-bacs
    # `pages/1_Settings.py`. A cost-centre picker (#index) leads to an edit form
    # (#edit / #update) for that cost centre's mailboxes, EUSA recipient +
    # signature, nightly run-days and the two SharePoint destinations. Where
    # bedlam-bacs kept this in a per-user config.toml, it now lives on the
    # CostCentre row so it is shared and multi-cost-centre.
    #
    # The SharePoint destinations are chosen with a Graph-backed folder picker
    # (browse sites -> drives -> folders); "Use this folder" stores the drive +
    # folder ids. Browsing is entirely server-rendered (GET params carry the
    # navigation state) so it needs no JavaScript and is testable with a fake
    # Graph client.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class SettingsController < FinanceController
      # Injection seam for tests: the app-only Graph client (SharePoint browse).
      class_attribute :graph_builder, default: -> { ::Reimbursements::GraphClient.new }

      before_action :set_cost_centre, only: %i[edit update]

      # Which CostCentre columns each SharePoint destination writes.
      FOLDER_COLUMNS = {
        "receipts" => { drive: :sharepoint_receipts_drive_id, folder: :sharepoint_receipts_folder_id },
        "bacs" => { drive: :sharepoint_bacs_drive_id, folder: :sharepoint_bacs_folder_id }
      }.freeze

      def index
        @title = "Reimbursements Settings"
        @cost_centres = ::Reimbursements::CostCentre.order(:name)
      end

      def edit
        @title = "Settings — #{@cost_centre.name}"
        setup_folder_picker if params[:picker].present?
      end

      def update
        params[:folder_purpose].present? ? save_folder : save_settings
      end

      private

      def set_cost_centre
        @cost_centre = ::Reimbursements::CostCentre.find_by!(key: params[:key])
      end

      def graph
        @graph ||= graph_builder.call
      end

      def edit_path
        edit_admin_reimbursements_setting_path(@cost_centre.key)
      end

      # --- Save the main settings form --------------------------------------

      def save_settings
        if @cost_centre.update(settings_params)
          redirect_to edit_path, notice: "Settings saved for #{@cost_centre.name}."
        else
          @title = "Settings — #{@cost_centre.name}"
          flash.now[:alert] = @cost_centre.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_entity
        end
      end

      def settings_params
        permitted = params.require(:cost_centre).permit(
          :receive_mailbox, :send_mailbox, :eusa_recipient, :eusa_signature_name
        )
        permitted[:nightly_run_days] = normalized_run_days
        permitted
      end

      # Checkbox values arrive as strings; keep valid Ruby wday numbers, sorted.
      def normalized_run_days
        Array(params.dig(:cost_centre, :nightly_run_days))
          .filter_map { |day| Integer(day, exception: false) }
          .select { |day| day.between?(0, 6) }
          .uniq.sort
      end

      # --- Save a SharePoint folder selection -------------------------------

      def save_folder
        columns = FOLDER_COLUMNS[params[:folder_purpose]]
        if columns.nil? || params[:drive_id].blank? || params[:folder_id].blank?
          return redirect_to(edit_path, alert: "Pick a folder before saving.")
        end

        @cost_centre.update!(columns[:drive] => params[:drive_id], columns[:folder] => params[:folder_id])
        redirect_to edit_path, notice: "#{params[:folder_purpose].humanize} folder saved."
      end

      # --- Graph-backed folder picker ---------------------------------------

      def setup_folder_picker
        @picker = params[:picker]
        @path = browse_path
        @site_id = params[:site_id].presence
        @drive_id = params[:drive_id].presence

        if @drive_id
          @items = graph.list_folder_contents(drive_id: @drive_id, item_id: @path.last&.dig(:id))
        elsif @site_id
          @drives = graph.list_drives(@site_id)
        else
          @sites = graph.list_sites(search: params[:q].presence || "*")
        end
      rescue StandardError => e
        flash.now[:alert] = "SharePoint browse failed: #{e.message}"
      end

      # The current breadcrumb: parallel path_ids/path_names params zipped into
      # [{ id:, name: }]. The tail is the folder being listed.
      def browse_path
        ids = Array(params[:path_ids])
        names = Array(params[:path_names])
        ids.each_with_index.map { |id, index| { id: id, name: names[index].to_s } }
      end
      helper_method :browse_path
    end
  end
end
