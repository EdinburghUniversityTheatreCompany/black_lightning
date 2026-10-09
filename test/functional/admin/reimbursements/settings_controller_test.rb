require "test_helper"

module Admin
  module Reimbursements
    class SettingsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      CC = ::Reimbursements::CostCentre

      # Canned Graph answers that record what was asked.
      Site = Struct.new(:id, :name, :web_url, keyword_init: true)
      Drive = Struct.new(:id, :name, keyword_init: true)
      Item = Struct.new(:id, :name, :folder, :web_url, keyword_init: true)

      class FakeGraph
        attr_reader :folder_calls, :site_calls, :mailbox_calls
        attr_accessor :fail_check_mailbox, :fail_get_site, :fail_list_folder_contents

        def initialize
          @folder_calls = []
          @site_calls = []
          @mailbox_calls = []
        end

        def check_mailbox(address)
          @mailbox_calls << address
          raise ::GraphAuth::AuthError, "Graph rejected the token (403)" if @fail_check_mailbox

          true
        end

        def get_site(site_url)
          @site_calls << site_url
          raise ::GraphAuth::Error, "site not granted (403)" if @fail_get_site

          Site.new(id: "site-1", name: "Finance Site", web_url: site_url)
        end

        def list_drives(site_id)
          [ Drive.new(id: "drive-#{site_id}", name: "Documents") ]
        end

        def list_folder_contents(drive_id:, item_id: nil)
          @folder_calls << [ drive_id, item_id ]
          raise ::GraphAuth::Error, "folder unreachable (403)" if @fail_list_folder_contents

          [ Item.new(id: "folder-A", name: "BACS", folder: true, web_url: "https://sp/a"),
            Item.new(id: "file-x", name: "notes.txt", folder: false, web_url: "https://sp/x") ]
        end
      end

      setup do
        @user = users(:member)
        grant_finance_permission(@user)
        @cost_centre = CC.default
        @graph = FakeGraph.new
        SettingsController.graph_builder = -> { @graph }
      end

      teardown do
        SettingsController.graph_builder = -> { ::Reimbursements::GraphClient.new }
      end

      # --- Picker (index) ----------------------------------------------------

      test "index lists every cost centre" do
        create_second_reimbursements_cost_centre
        sign_in @user

        get :index

        assert_response :success
        assert_equal 2, assigns(:cost_centres).size
        assert_includes response.body, @cost_centre.name
        assert_includes response.body, "Bedlam Termtime"
      end

      # --- Edit --------------------------------------------------------------

      test "edit renders the routine settings and links out to the Microsoft setup page" do
        sign_in @user
        get :edit, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, @cost_centre.receive_mailbox
        assert_includes response.body, "Nightly reminders run on"
        assert_select "a[href=?] span[aria-hidden=true]", admin_reimbursements_settings_path, text: "←"
        assert_includes response.body, 'data-turbo-submits-with="Testing'
        assert_select "a[href=?]", microsoft_setup_admin_reimbursements_setting_path(@cost_centre.key)
        # Runbook markers only: "Sites.Selected" still appears beside the URL field.
        assert_not_includes response.body, "Test-ServicePrincipalAuthorization"
        assert_not_includes response.body, "graph.microsoft.com/v1.0/sites"
        assert_not_includes response.body, "docs/graph-mailbox-rbac.ps1"
      end

      test "the Microsoft setup page fills in this centre's mailboxes and SharePoint site" do
        receive_mailbox = @cost_centre.receive_mailbox
        @cost_centre.update!(send_mailbox: "outbox@bedlamfringe.co.uk",
                             sharepoint_site_url: "https://tenant.sharepoint.com/sites/Finance")
        sign_in @user
        get :microsoft_setup, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "What IT has to do in Microsoft 365"
        assert_includes response.body, "docs/graph-mailbox-rbac.ps1"
        assert_includes response.body,
          "Test-ServicePrincipalAuthorization -Identity b874d491-4edf-4b76-839d-84e534c7f7c0"
        assert_includes response.body, "-Resource #{receive_mailbox}"
        assert_includes response.body, "-Resource outbox@bedlamfringe.co.uk"
        # The scope filter is replaced wholesale, so the page must say so.
        assert_includes response.body, "replaced, not added to"
        assert_includes response.body, "bin/rails graph:mailboxes"
        assert_includes response.body, "Sites.Selected"
        assert_includes response.body, "sites/tenant.sharepoint.com:/sites/Finance"
        assert_includes response.body, "/permissions"
        assert_select "a[href=?]", edit_admin_reimbursements_setting_path(@cost_centre.key)
        # The retired group only constrained Entra-granted Mail.*, now revoked:
        # adding a mailbox to it does nothing.
        assert_not_includes response.body, "Add-DistributionGroupMember"
        assert_not_includes response.body, "Test-ApplicationAccessPolicy"
        assert_not_includes response.body, "Reimbursements App Access"
      end

      test "edit carries this cost centre's nominal codes, editable in place" do
        termtime = create_second_reimbursements_cost_centre
        code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                  cost_centre: @cost_centre)
        create_reimbursements_nominal_code(code: "555555", label: "Termtime printing",
                                           cost_centre: termtime)
        sign_in @user

        get :edit, params: { key: @cost_centre.key }

        assert_select "#nominal_codes div[id^=nominal_code_]", 1
        assert_select "#nominal_code_#{code.record_id} span.font-mono", text: "432320"
        assert_select "#nominal_codes input##{"label_#{code.record_id}"}[value=?]", "Marketing"
        assert_select "#nominal_codes form[action=?]",
                      admin_reimbursements_nominal_codes_path(@cost_centre.key)
        assert_not_includes response.body, "Termtime printing"
      end

      test "a centre with no nominal codes is told to add them on this page" do
        sign_in @user

        get :edit, params: { key: @cost_centre.key }

        assert_select "#nominal_codes p", text: "No codes listed for #{@cost_centre.name} yet. Add them below."
      end

      # A form inside a form is invalid HTML; its submit silently does nothing.
      test "the nominal codes section is not nested inside the cost centre form" do
        create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        sign_in @user

        get :edit, params: { key: @cost_centre.key }

        assert_select "form #nominal_codes", false,
                      "the nominal codes section must not sit inside another form"
      end

      test "the nominal codes section states what is booked against each code" do
        used = create_reimbursements_nominal_code(code: "432320", cost_centre: @cost_centre)
        unused = create_reimbursements_nominal_code(code: "999999", cost_centre: @cost_centre)
        create_reimbursements_budget(name: "Marketing", nominal_code: "432320",
                                     cost_centre: @cost_centre)
        create_reimbursements_actual(nominal_code: "432320", cost_centre: @cost_centre)
        sign_in @user

        get :edit, params: { key: @cost_centre.key }

        assert_includes response.body, "1 budget line and 1 ledger row booked here"
        assert_select "#nominal_code_#{used.record_id} button", text: "Retire"
        assert_includes response.body, "Nothing booked here"
        assert_select "#nominal_code_#{unused.record_id} button", text: "Delete"
        assert_select "#nominal_code_#{unused.record_id} button", text: "Retire", count: 0
      end

      test "edit 404s for an unknown cost centre" do
        sign_in @user
        get :edit, params: { key: "nope" }
        assert_response :not_found
      end

      # --- Update: settings --------------------------------------------------

      test "update writes every field on the settings form" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, cost_centre: {
          short_code: "BF", receive_mailbox: "in@fringe.co", send_mailbox: "out@fringe.co",
          eusa_recipient: "eusa@ed.ac.uk", eusa_contact_name: "Craig",
          eusa_signature_name: "Fringe Finance",
          authoriser_name: "Jo Producer", authoriser_designation: "Fringe Treasurer",
          sharepoint_site_url: "https://tenant.sharepoint.com/sites/Fringe",
          notification_email: "finance@bedlamfringe.co.uk",
          nightly_run_days: %w[1 3 5]
        } }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        @cost_centre.reload
        assert_equal "BF", @cost_centre.short_code
        assert_equal "in@fringe.co", @cost_centre.receive_mailbox
        assert_equal "out@fringe.co", @cost_centre.send_mailbox
        assert_equal "eusa@ed.ac.uk", @cost_centre.eusa_recipient
        assert_equal "Craig", @cost_centre.eusa_contact_name
        assert_equal "Fringe Finance", @cost_centre.eusa_signature_name
        assert_equal "Jo Producer", @cost_centre.authoriser_name
        assert_equal "Fringe Treasurer", @cost_centre.authoriser_designation
        assert_equal "https://tenant.sharepoint.com/sites/Fringe", @cost_centre.sharepoint_site_url
        assert_equal [ "finance@bedlamfringe.co.uk" ], @cost_centre.notification_emails
        assert_equal [ 1, 3, 5 ], @cost_centre.nightly_run_days
      end

      test "update hides a cost centre's budgets from submitters" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, cost_centre: {
          hidden_from_submitters: "1", nightly_run_days: @cost_centre.nightly_run_days
        } }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        assert_predicate @cost_centre.reload, :hidden_from_submitters?
        get :index
        assert_select ".bg-gray-100", text: "Hidden from submitters"
      end

      # settings_params turns a missing nightly_run_days into [], which fails
      # validation and aborts the save.
      test "update with no run-days checked is rejected, not saved as an empty schedule" do
        @cost_centre.update!(nightly_run_days: [ 2, 4 ])
        sign_in @user

        patch :update, params: { key: @cost_centre.key, cost_centre: {
          receive_mailbox: "in@fringe.co", send_mailbox: "out@fringe.co"
        } }

        assert_response :unprocessable_entity
        assert_includes response.body, "must include at least one weekday"
        assert_equal [ 2, 4 ], @cost_centre.reload.nightly_run_days,
                     "clearing every run-day would silently disable the nightly for this cost centre"
      end

      # --- Folder picker -----------------------------------------------------

      test "picker browses the cost centre's configured site and lists its libraries" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        sign_in @user
        get :edit, params: { key: @cost_centre.key, picker: "receipts" }

        assert_response :success
        assert_includes response.body, "Finance Site"
        assert_includes response.body, "Documents"
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

      test "using a folder on a centre with no notification email says why instead of 500ing" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        @cost_centre.update_column(:notification_email, nil)
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "receipts",
                                 drive_id: "drive-site-1", folder_id: "folder-A" }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        assert_match(/Notification email/, flash[:alert])
        assert_nil @cost_centre.reload.sharepoint_receipts_drive_id
      end

      test "saving a folder with a blank id is refused" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "bacs",
                                 drive_id: "drive-1", folder_id: "" }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        assert_match(/Pick a folder/, flash[:alert])
        assert_nil @cost_centre.reload.sharepoint_bacs_folder_id
      end

      # The ids come from hidden fields, and this folder receives bank details.
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
        @graph.fail_list_folder_contents = true
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
        assert_includes response.body, "Granted and reachable"
        assert_includes response.body, "Reachable."
        # The picker heading's wording, not "Bacs folder".
        assert_includes response.body, "BACS request folder"
        assert_includes response.body, "Receipts folder"
        assert_not_includes response.body, "Bacs folder"
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
        @graph.fail_check_mailbox = true
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "403"
        assert_includes response.body, "Exchange management scope"
      end

      test "access check flags a SharePoint site the app can't reach" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        @graph.fail_get_site = true
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "site not granted (403)"
        assert_includes response.body, "Grant the app write on this site"
      end

      test "access check flags a configured folder the app can't reach" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance",
                             sharepoint_receipts_drive_id: "drv", sharepoint_receipts_folder_id: "fld")
        @graph.fail_list_folder_contents = true
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }

        assert_response :success
        assert_includes response.body, "folder unreachable (403)"
      end

      test "the folder picker's browse failure re-renders edit with an alert, not a 500" do
        @cost_centre.update!(sharepoint_site_url: "https://sp.sharepoint.com/sites/Finance")
        @graph.fail_get_site = true
        sign_in @user

        get :edit, params: { key: @cost_centre.key, picker: "receipts" }

        assert_response :success
        assert_includes response.body, "SharePoint browse failed"
      end

      test "access check answers a turbo stream that updates the results in place" do
        sign_in @user

        post :test_access, params: { key: @cost_centre.key }, as: :turbo_stream

        assert_response :success
        assert_includes response.media_type, "turbo-stream"
        assert_includes response.body, "access_check_results"
      end

      # --- New / Create: cost-centre form ------------------------------------

      test "new renders the create-cost-centre form posting to the collection" do
        sign_in @user
        get :new

        assert_response :success
        assert_select "form[action=?]", admin_reimbursements_settings_path
        assert_includes response.body, "Advanced"
      end

      test "create adds a cost centre and redirects to its edit page to finish setup" do
        sign_in @user

        assert_difference -> { CC.count }, 1 do
          post :create, params: { cost_centre: {
            name: "Bedlam Termtime", eusa_code: "BED",
            receive_mailbox: "termtime-in@example.co", send_mailbox: "termtime-out@example.co",
            notification_email: "finance@bedlamfringe.co.uk; business@bedlamtheatre.co.uk"
          } }
        end

        created = CC.find_by(eusa_code: "BED")
        assert_equal "bedlam-termtime", created.key, "key auto-derived from the name"
        assert_equal [ "finance@bedlamfringe.co.uk", "business@bedlamtheatre.co.uk" ],
                     created.notification_emails
        assert_redirected_to edit_admin_reimbursements_setting_path(created.key)
        assert_match(/mailbox|sharepoint/i, flash[:notice])
      end

      test "create honours a manual key override from the Advanced section" do
        sign_in @user

        post :create, params: { cost_centre: {
          name: "Some Long Name", key: "shortkey", eusa_code: "SLN",
          receive_mailbox: "sln-in@example.co", send_mailbox: "sln-out@example.co",
          notification_email: "sln-finance@example.co"
        } }

        assert_equal "shortkey", CC.find_by(eusa_code: "SLN").key
      end

      test "create rejects a blank name without creating a row" do
        sign_in @user

        assert_no_difference -> { CC.count } do
          post :create, params: { cost_centre: {
            name: "", eusa_code: "NB1",
            receive_mailbox: "nb-in@example.co", send_mailbox: "nb-out@example.co",
            notification_email: "nb@example.co"
          } }
        end

        assert_response :unprocessable_entity
      end

      test "create denies members without the finance permission" do
        sign_in users(:committee)

        assert_no_difference -> { CC.count } do
          post :create, params: { cost_centre: {
            name: "Sneaky", eusa_code: "SNK",
            receive_mailbox: "snk-in@example.co", send_mailbox: "snk-out@example.co"
          } }
        end

        assert_response :forbidden
      end
    end
  end
end
