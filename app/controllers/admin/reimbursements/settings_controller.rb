module Admin
  module Reimbursements
    ##
    # Per-cost-centre settings: mailboxes, EUSA recipient and signature, nightly
    # run-days and the two SharePoint destinations. The folder picker browses the
    # configured site's drives -> folders server-side (GET params carry the
    # navigation), so it needs no JavaScript and tests with a fake Graph client.
    class SettingsController < FinanceController
      include ListsNominalCodes

      before_action :set_cost_centre, only: %i[edit update test_access microsoft_setup]
      # Every action that can render :edit needs the nominal-codes list.
      before_action :set_nominal_codes, only: %i[edit update test_access]

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

      # Only the required fields; the rest is set on the edit page #create lands on.
      def new
        @title = "New cost centre"
        @cost_centre = ::Reimbursements::CostCentre.new
      end

      def create
        @cost_centre = ::Reimbursements::CostCentre.new(create_params)
        if @cost_centre.save
          redirect_to edit_admin_reimbursements_setting_path(@cost_centre.key),
                      notice: "Cost centre created. Now configure its mailboxes, EUSA details and " \
                              "SharePoint destinations below."
        else
          @title = "New cost centre"
          flash.now[:alert] = @cost_centre.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      end

      def edit
        @title = "Settings: #{@cost_centre.name}"
        setup_folder_picker if params[:picker].present?
      end

      # The one-off Microsoft 365 steps, on a page of their own so it can be sent
      # to IT. No set_nominal_codes: it shows none of that panel.
      def microsoft_setup
        @title = "Microsoft setup: #{@cost_centre.name}"
      end

      def update
        params[:folder_purpose].present? ? save_folder : save_settings
      end

      # Probes the mailboxes and SharePoint destinations with the app's own credentials.
      def test_access
        @title = "Settings: #{@cost_centre.name}"
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

      def set_nominal_codes
        load_nominal_codes(@cost_centre)
      end

      def edit_path
        edit_admin_reimbursements_setting_path(@cost_centre.key)
      end

      # --- Save the main settings form --------------------------------------

      def save_settings
        if @cost_centre.update(settings_params)
          redirect_to edit_path, notice: "Settings saved for #{@cost_centre.name}."
        else
          @title = "Settings: #{@cost_centre.name}"
          flash.now[:alert] = @cost_centre.errors.full_messages.to_sentence
          render :edit, status: :unprocessable_entity
        end
      end

      # The new form collects only the required fields. +key+ may be blank: the
      # model derives it from the name.
      def create_params
        params.require(:cost_centre).permit(
          :key, :name, :eusa_code, :short_code, :receive_mailbox, :send_mailbox, :notification_email
        )
      end

      def settings_params
        permitted = params.require(:cost_centre).permit(
          :receive_mailbox, :send_mailbox, :eusa_recipient, :eusa_contact_name, :eusa_signature_name,
          :sharepoint_site_url, :notification_email
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
          return redirect_to(edit_path, alert: "That folder could not be verified against SharePoint. " \
                                               "Please pick it again.")
        end

        @cost_centre.update!(columns[:drive] => params[:drive_id], columns[:folder] => params[:folder_id])
        redirect_to edit_path, notice: "#{folder_label(params[:folder_purpose])} saved."
      end

      # The ids arrive in hidden fields, which a client can tamper with, and the
      # BACS folder receives bank details: so check with Graph that the drive is
      # on this centre's own site and the folder exists in it.
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

      # The fix is the Exchange management scope, not the retired "Reimbursements
      # App Access" group: adding a mailbox to that group now changes nothing.
      def mailbox_check(mailbox)
        graph.check_mailbox(mailbox)
        Check.new(label: "Mailbox #{mailbox}", status: :ok,
                  detail: "Reachable (it's in the app's Exchange management scope).")
      rescue StandardError => e
        Check.new(label: "Mailbox #{mailbox}", status: :fail,
                  detail: "#{e.message}. Add it to the app's Exchange management scope, passing the full " \
                          "mailbox list (commands below). Allow up to 2 hours for the app's permission " \
                          "cache before re-checking.")
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

      # Human label for a folder purpose, degrading to a humanized key rather
      # than raising if a future FOLDER_COLUMNS entry lacks a FOLDER_LABELS one.
      def folder_label(purpose)
        FOLDER_LABELS.fetch(purpose) { "#{purpose.to_s.humanize} folder" }
      end

      def folder_checks
        FOLDER_COLUMNS.map do |purpose, columns|
          label = folder_label(purpose)
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

      # Sites.Selected cannot search sites, so the picker starts from the
      # configured site URL; without one the view asks for it.
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

      # The breadcrumb from parallel path_ids/path_names params; the last is the folder listed.
      def browse_path
        ids = Array(params[:path_ids])
        names = Array(params[:path_names])
        ids.each_with_index.map { |id, index| { id: id, name: names[index].to_s } }
      end
      helper_method :browse_path
    end
  end
end
