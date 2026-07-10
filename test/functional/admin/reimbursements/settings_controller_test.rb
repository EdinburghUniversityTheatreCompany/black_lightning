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
        attr_reader :folder_calls

        def initialize
          @folder_calls = []
        end

        def list_sites(search:)
          [ Site.new(id: "site-1", name: "Finance Site (#{search})", web_url: "https://sp/finance") ]
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

      test "picker lists SharePoint sites" do
        sign_in @user
        get :edit, params: { key: @cost_centre.key, picker: "receipts", q: "finance" }

        assert_response :success
        assert_includes response.body, "Finance Site (finance)"
      end

      test "picker lists folder contents once a drive is chosen" do
        sign_in @user
        get :edit, params: { key: @cost_centre.key, picker: "bacs", site_id: "site-1", drive_id: "drive-1" }

        assert_response :success
        assert_includes response.body, "BACS"
        assert_equal [ [ "drive-1", nil ] ], @graph.folder_calls
      end

      test "using a folder stores its drive and folder ids" do
        sign_in @user

        patch :update, params: { key: @cost_centre.key, folder_purpose: "receipts",
                                 drive_id: "drive-1", folder_id: "folder-A" }

        assert_redirected_to edit_admin_reimbursements_setting_path(@cost_centre.key)
        @cost_centre.reload
        assert_equal "drive-1", @cost_centre.sharepoint_receipts_drive_id
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
    end
  end
end
