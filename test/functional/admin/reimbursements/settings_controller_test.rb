require "test_helper"

module Admin
  module Reimbursements
    class SettingsControllerTest < ActionController::TestCase
      CC = ::Reimbursements::CostCentre

      # Fake Graph client for the SharePoint folder picker: returns canned
      # sites/drives/folder contents and records what it was asked to browse.
      Site = Struct.new(:id, :name, :web_url, keyword_init: true)
      Drive = Struct.new(:id, :name, keyword_init: true)
      Item = Struct.new(:id, :name, :folder, :web_url, keyword_init: true)

      class FakeGraph
        attr_reader :folder_calls, :site_calls, :mailbox_calls

        def initialize(mailbox_ok: true)
          @folder_calls = []
          @site_calls = []
          @mailbox_calls = []
          @mailbox_ok = mailbox_ok
        end

        def check_mailbox(address)
          @mailbox_calls << address
          raise ::Reimbursements::GraphAuth::AuthError, "Graph rejected the token (403)" unless @mailbox_ok

          true
        end

        def get_site(site_url)
          @site_calls << site_url
          Site.new(id: "site-1", name: "Finance Site", web_url: site_url)
        end

        def list_drives(site_id)
          [ Drive.new(id: "drive-#{site_id}", name: "Documents") ]
        end

        def list_folder_contents(drive_id:, item_id: nil)
          @folder_calls << [ drive_id, item_id ]
          [ Item.new(id: "folder-A", name: "BACS", folder: true, web_url: "https://sp/a"),
            Item.new(id: "file-x", name: "notes.txt", folder: false, web_url: "https://sp/x") ]
        end
      end

      setup do
        finance = Role.create!(name: "Business Manager")
        finance.permissions << Admin::Permission.create(action: "manage", subject_class: "reimbursements_finance")
        users(:member).add_role("Business Manager")
        @user = users(:member)
        @cost_centre = CC.default
        @graph = FakeGraph.new
        SettingsController.graph_builder = -> { @graph }
      end

      teardown do
        SettingsController.graph_builder = -> { ::Reimbursements::GraphClient.new }
      end

      # --- Auth gating -------------------------------------------------------

      test "requires sign-in" do
        get :index
        assert_redirected_to new_user_session_path
      end

      test "denies members without the finance permission" do
        sign_in users(:committee)
        get :index
        assert_response :forbidden
      end

      test "the producer portal permission alone does not grant finance access" do
        producer = Role.create!(name: "Producer")
        producer.permissions << Admin::Permission.create(action: "access", subject_class: "reimbursements")
        other = users(:member_with_phone_number)
        other.add_role("Producer")
        sign_in other

        get :index

        assert_response :forbidden
      end

      # --- Picker (index) ----------------------------------------------------

      test "index lists every cost centre" do
        CC.create!(key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
                   receive_mailbox: "t@x.co", send_mailbox: "t@x.co")
        sign_in @user

        get :index

        assert_response :success
        assert_equal 2, assigns(:cost_centres).size
        assert_includes response.body, @cost_centre.name
        assert_includes response.body, "Bedlam Termtime"
      end

      # --- Edit --------------------------------------------------------------

      test "edit renders the settings form for a cost centre" do
        sign_in @user
        get :edit, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, @cost_centre.receive_mailbox
        assert_includes response.body, "Nightly auto-submit runs on"
      end

      test "edit shows the Exchange grant command filled in with this mailbox" do
        sign_in @user
        get :edit, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "Microsoft access for this cost centre"
        assert_includes response.body,
          %(Add-DistributionGroupMember -Identity "Reimbursements App Access" -Member #{@cost_centre.receive_mailbox})
        assert_includes response.body,
          "Test-ApplicationAccessPolicy -Identity #{@cost_centre.receive_mailbox} -AppId b874d491-4edf-4b76-839d-84e534c7f7c0"
      end

      test "edit shows a separate grant block when the send mailbox differs" do
        @cost_centre.update!(send_mailbox: "outbox@bedlamfringe.co.uk")
        sign_in @user
        get :edit, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "-Member #{@cost_centre.receive_mailbox}"
        assert_includes response.body, "-Member outbox@bedlamfringe.co.uk"
      end

      test "edit shows the SharePoint Sites.Selected grant with the site path filled in" do
        @cost_centre.update!(sharepoint_site_url: "https://tenant.sharepoint.com/sites/Finance")
        sign_in @user
        get :edit, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "Sites.Selected"
        assert_includes response.body, "sites/tenant.sharepoint.com:/sites/Finance"
        assert_includes response.body, "/permissions"
      end

      test "edit 404s for an unknown cost centre" do
        sign_in @user
        get :edit, params: { key: "nope" }
        assert_response :not_found
      end

      # --- Update: settings --------------------------------------------------

      test "update writes mailboxes, recipient, signature and run-days" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, cost_centre: {
          receive_mailbox: "in@fringe.co", send_mailbox: "out@fringe.co",
          eusa_recipient: "eusa@ed.ac.uk", eusa_signature_name: "Fringe Finance",
          nightly_run_days: %w[1 3 5]
        } }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        @cost_centre.reload
        assert_equal "in@fringe.co", @cost_centre.receive_mailbox
        assert_equal "out@fringe.co", @cost_centre.send_mailbox
        assert_equal "eusa@ed.ac.uk", @cost_centre.eusa_recipient
        assert_equal "Fringe Finance", @cost_centre.eusa_signature_name
        assert_equal [ 1, 3, 5 ], @cost_centre.nightly_run_days
      end

      test "update saves the SharePoint site URL" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, cost_centre: {
          receive_mailbox: "in@fringe.co", send_mailbox: "out@fringe.co",
          sharepoint_site_url: "https://tenant.sharepoint.com/sites/Fringe"
        } }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        assert_equal "https://tenant.sharepoint.com/sites/Fringe", @cost_centre.reload.sharepoint_site_url
      end

      test "update with no run-days checked clears the schedule" do
        @cost_centre.update!(nightly_run_days: [ 2, 4 ])
        sign_in @user

        patch :update, params: { key: @cost_centre.key, cost_centre: {
          receive_mailbox: "in@fringe.co", send_mailbox: "out@fringe.co"
        } }

        assert_equal [], @cost_centre.reload.nightly_run_days
      end

      test "update rejects a blank required mailbox without saving" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, cost_centre: {
          receive_mailbox: "", send_mailbox: "out@fringe.co"
        } }

        assert_response :unprocessable_entity
        assert_not_equal "", @cost_centre.reload.receive_mailbox
      end

      # --- Folder picker -----------------------------------------------------

      test "picker browses the cost centre's configured site and lists its libraries" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        sign_in @user
        get :edit, params: { key: @cost_centre.key, picker: "receipts" }

        assert_response :success
        assert_includes response.body, "Finance Site"                            # site resolved by URL
        assert_includes response.body, "Documents"                               # its library listed
        assert_equal [ "https://sp.sharepoint.com/sites/Finance" ], @graph.site_calls
      end

      test "picker prompts to set a site URL when none is configured" do
        @cost_centre.update!(sharepoint_site_url: nil)
        sign_in @user
        get :edit, params: { key: @cost_centre.key, picker: "receipts" }

        assert_response :success
        assert_includes response.body, "only reaches the site you've granted it"
        assert_empty @graph.site_calls
      end

      test "picker lists folder contents once a drive is chosen" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        sign_in @user
        get :edit, params: { key: @cost_centre.key, picker: "bacs", drive_id: "drive-1" }

        assert_response :success
        assert_includes response.body, "BACS"
        assert_equal [ [ "drive-1", nil ] ], @graph.folder_calls
      end

      test "using a folder stores its drive and folder ids" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "receipts",
                                 drive_id: "drive-site-1", folder_id: "folder-A" }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        @cost_centre.reload
        assert_equal "drive-site-1", @cost_centre.sharepoint_receipts_drive_id
        assert_equal "folder-A", @cost_centre.sharepoint_receipts_folder_id
      end

      test "saving a folder with a blank id is refused" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "bacs",
                                 drive_id: "drive-1", folder_id: "" }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        assert_match(/Pick a folder/, flash[:alert])
        assert_nil @cost_centre.reload.sharepoint_bacs_folder_id
      end

      # A save_folder POST's drive_id/folder_id come from hidden form fields —
      # still client-controllable — and this is exactly where bank-detail-
      # bearing BACS files get uploaded, so a tampered value must be re-verified
      # against Graph rather than trusted outright.
      test "a drive_id that doesn't belong to the cost centre's own site is refused, not trusted outright" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "receipts",
                                 drive_id: "some-unrelated-drive", folder_id: "folder-A" }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        assert_match(/could not be verified/, flash[:alert])
        assert_nil @cost_centre.reload.sharepoint_receipts_drive_id
      end

      test "a folder_id that doesn't resolve under the verified drive is refused" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        @graph.define_singleton_method(:list_folder_contents) do |**|
          raise ::Reimbursements::GraphAuth::Error, "not found (404)"
        end
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "receipts",
                                 drive_id: "drive-site-1", folder_id: "bogus" }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        assert_match(/could not be verified/, flash[:alert])
        assert_nil @cost_centre.reload.sharepoint_receipts_drive_id
      end

      test "no configured SharePoint site refuses any folder save" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "receipts",
                                 drive_id: "drive-site-1", folder_id: "folder-A" }

        assert_match(/could not be verified/, flash[:alert])
        assert_nil @cost_centre.reload.sharepoint_receipts_drive_id
      end

      # --- Access check ------------------------------------------------------

      test "access check reports reachable mailboxes, site and folders" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance",
                             sharepoint_receipts_drive_id: "drv", sharepoint_receipts_folder_id: "fld",
                             sharepoint_bacs_drive_id: "drv2", sharepoint_bacs_folder_id: "fld2")
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "Mailbox #{@cost_centre.receive_mailbox}"
        assert_includes response.body, "Granted and reachable"                 # SharePoint site OK
        assert_includes response.body, "Reachable."                            # folders OK
        assert_includes @graph.mailbox_calls, @cost_centre.receive_mailbox
        assert_equal [ "https://sp.sharepoint.com/sites/Finance" ], @graph.site_calls
        assert_equal [ [ "drv", "fld" ], [ "drv2", "fld2" ] ], @graph.folder_calls
      end

      test "access check skips a SharePoint site that isn't configured yet" do
        @cost_centre.update!(sharepoint_site_url: nil)
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "No site URL set yet"
        assert_empty @graph.site_calls
      end

      test "access check flags a mailbox the app can't reach" do
        SettingsController.graph_builder = -> { FakeGraph.new(mailbox_ok: false) }
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "403"
        assert_includes response.body, "Reimbursements App Access"             # remediation hint
      end

      test "the access-check button shows a testing state while it runs" do
        sign_in @user
        get :edit, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, 'data-turbo-submits-with="Testing'
      end

      test "access check answers a turbo stream that updates the results in place" do
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }, as: :turbo_stream

        assert_response :success
        assert_includes response.media_type, "turbo-stream"
        assert_includes response.body, "access_check_results"
      end

      test "test_access denies members without the finance permission" do
        sign_in users(:committee)
        post :test_access, params: { key: @cost_centre.key }
        assert_response :forbidden
      end
    end
  end
end
