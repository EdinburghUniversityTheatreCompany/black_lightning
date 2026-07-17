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
      before_action :set_cost_centre, only: %i[edit update test_access]

      # Which CostCentre columns each SharePoint destination writes.
      FOLDER_COLUMNS = {
        "receipts" => { drive: :sharepoint_receipts_drive_id, folder: :sharepoint_receipts_folder_id },
        "bacs" => { drive: :sharepoint_bacs_drive_id, folder: :sharepoint_bacs_folder_id }
      }.freeze

      # Human labels for each destination — matches the folder-picker headings
      # on the edit page. `humanize` would render "bacs" as "Bacs", not "BACS".
      FOLDER_LABELS = {
        "receipts" => "Receipts folder",
        "bacs" => "BACS request folder"
      }.freeze

      # One row of the "Run access check" results.
      Check = Struct.new(:label, :status, :detail, keyword_init: true)

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

      # Probe this cost centre's mailboxes and SharePoint destinations with the
      # app's own credentials, so the business manager can confirm the Microsoft
      # grants worked before relying on email-in or Build Batch. Renders the edit
      # page with a per-check pass/fail list.
      def test_access
        @title = "Settings — #{@cost_centre.name}"
        @access_checks = run_access_checks
        respond_to do |format|
          format.turbo_stream
          format.html { render :edit }
        end
      end

      private

      def set_cost_centre
        @cost_centre = ::Reimbursements::CostCentre.find_by!(key: params[:key])
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
          :receive_mailbox, :send_mailbox, :eusa_recipient, :eusa_signature_name,
          :sharepoint_site_url
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

        unless verified_folder?(params[:drive_id], params[:folder_id])
          return redirect_to(edit_path, alert: "That folder could not be verified against SharePoint " \
                                               "— please pick it again.")
        end

        @cost_centre.update!(columns[:drive] => params[:drive_id], columns[:folder] => params[:folder_id])
        redirect_to edit_path, notice: "#{FOLDER_LABELS.fetch(params[:folder_purpose])} saved."
      end

      # drive_id/folder_id arrive as hidden form fields the browse flow
      # populated, but hidden fields are still client-controllable — a
      # tampered value must not be trusted outright, since this setting is
      # exactly where bank-detail-bearing BACS files get uploaded. Re-verify
      # against Graph: the drive genuinely belongs to this cost centre's own
      # configured SharePoint site, and the folder genuinely exists as a real
      # folder within it (a nonexistent/wrong-type item 404s from Graph).
      def verified_folder?(drive_id, folder_id)
        return false if @cost_centre.sharepoint_site_url.blank?

        site = graph.get_site(@cost_centre.sharepoint_site_url)
        return false unless graph.list_drives(site.id).any? { |drive| drive.id == drive_id }

        graph.list_folder_contents(drive_id: drive_id, item_id: folder_id)
        true
      rescue StandardError => e
        Rails.logger.warn("Reimbursements folder verification failed for #{@cost_centre.key}: #{e.message}")
        false
      end

      # --- Microsoft access check -------------------------------------------

      def run_access_checks
        mailboxes = [ @cost_centre.receive_mailbox, @cost_centre.send_mailbox ].map(&:presence).compact.uniq
        mailboxes.map { |mailbox| mailbox_check(mailbox) } + [ site_check ] + folder_checks
      end

      def mailbox_check(mailbox)
        graph.check_mailbox(mailbox)
        Check.new(label: "Mailbox #{mailbox}", status: :ok, detail: "Reachable (it's in the app-access group).")
      rescue StandardError => e
        Check.new(label: "Mailbox #{mailbox}", status: :fail,
                  detail: "#{e.message}. Add it to the Reimbursements App Access group (commands below).")
      end

      def site_check
        return Check.new(label: "SharePoint site", status: :skip, detail: "No site URL set yet.") if
          @cost_centre.sharepoint_site_url.blank?

        site = graph.get_site(@cost_centre.sharepoint_site_url)
        graph.list_drives(site.id)
        Check.new(label: "SharePoint site (#{site.name})", status: :ok, detail: "Granted and reachable.")
      rescue StandardError => e
        Check.new(label: "SharePoint site", status: :fail,
                  detail: "#{e.message}. Grant the app write on this site (Sites.Selected, command below).")
      end

      def folder_checks
        FOLDER_COLUMNS.map do |purpose, columns|
          label = FOLDER_LABELS.fetch(purpose)
          drive = @cost_centre.public_send(columns[:drive])
          folder = @cost_centre.public_send(columns[:folder])
          next Check.new(label: label, status: :skip, detail: "Not chosen yet.") if
            drive.blank? || folder.blank?

          graph.list_folder_contents(drive_id: drive, item_id: folder)
          Check.new(label: label, status: :ok, detail: "Reachable.")
        rescue StandardError => e
          Check.new(label: label, status: :fail, detail: e.message)
        end
      end

      # --- Graph-backed folder picker ---------------------------------------

      # Under Sites.Selected the app can't search sites, so the picker starts from
      # the cost centre's configured site URL (resolved to a Graph site), then
      # lists that site's drives and folders. Without a site URL there's nothing
      # to browse — the view prompts to set one first.
      def setup_folder_picker
        @picker = params[:picker]
        @path = browse_path
        @drive_id = params[:drive_id].presence

        if @cost_centre.sharepoint_site_url.blank?
          @site_missing = true
          return
        end

        @site = graph.get_site(@cost_centre.sharepoint_site_url)
        @site_id = @site.id

        if @drive_id
          @items = graph.list_folder_contents(drive_id: @drive_id, item_id: @path.last&.dig(:id))
        else
          @drives = graph.list_drives(@site_id)
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
