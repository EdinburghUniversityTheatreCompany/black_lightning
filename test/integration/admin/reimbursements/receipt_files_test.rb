require "test_helper"

module Admin
  module Reimbursements
    ##
    # Receipts are served BY THE APP, so the permission that gates a claim gates
    # its receipt too. Before this, they went out over ActiveStorage's own
    # routes, which Rails documents as "publicly accessible by default... the
    # generated URLs are hard to guess, but permanent by design" — so a receipt
    # link, which is a document carrying someone's home address, worked forever
    # for anyone who came by it, signed in or not.
    #
    # An integration test rather than a functional one: the streaming these
    # actions do is real middleware work, and the point is what actually comes
    # back over the wire.
    class ReceiptFilesTest < ActionDispatch::IntegrationTest
      include ReimbursementsTestHelpers
      include Devise::Test::IntegrationHelpers

      RECEIPT_BYTES = "%PDF-1.4 42 Acacia Avenue, Edinburgh".freeze

      setup do
        backend = -> { Permission.create(action: "access", subject_class: "backend") }
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        producer.permissions << backend.call
        finance = Role.create!(name: "Reimbursements Finance")
        finance.permissions << Permission.create(action: "manage", subject_class: "reimbursements_finance")
        finance.permissions << backend.call
        backend_only = Role.create!(name: "Backend Only")
        backend_only.permissions << backend.call

        @submitter = users(:member)
        @submitter.add_role("Producer")
        @submitter_person = create_reimbursements_person(email: @submitter.email, name: "Pat Producer")

        @stranger = FactoryBot.create(:user, email: "stranger@example.com")
        @stranger.add_role("Producer")
        create_reimbursements_person(email: @stranger.email, name: "Sam Stranger")

        @owner = FactoryBot.create(:user, email: "owner@example.com")
        @owner.add_role("Producer")
        @owner_person = create_reimbursements_person(email: @owner.email, name: "Olive Owner")

        @finance_user = FactoryBot.create(:user, email: "finance@example.com")
        @finance_user.add_role("Reimbursements Finance")

        @backend_only_user = FactoryBot.create(:user, email: "backend-only@example.com")
        @backend_only_user.add_role("Backend Only")

        @budget = create_reimbursements_budget(owners: [ @owner_person ])
        @expense = create_reimbursements_expense(person: @submitter_person, budget: @budget, receipt: false)
        attach_test_receipt(@expense, filename: "receipt.pdf", bytes: RECEIPT_BYTES)
        @receipt = @expense.receipts.first
      end

      def download_path = @receipt.download_url
      def inline_path = @receipt.url

      # --- The hole this closes ------------------------------------------------

      test "a receipt is not served to anyone who is not signed in" do
        get inline_path

        assert_redirected_to new_user_session_path
        assert_not response.body.include?("Acacia Avenue")
      end

      test "no ActiveStorage URL for a receipt is handed out any more" do
        %w[url download_url thumbnail_url].each do |accessor|
          value = @receipt.public_send(accessor)
          next if value.blank?

          assert_not value.start_with?("/rails/active_storage"),
                     "#{accessor} still points at the permanent, unauthenticated ActiveStorage route"
          assert value.start_with?("/admin/reimbursements/"),
                 "#{accessor} should be an app route that checks permissions, got #{value}"
        end
      end

      # --- Who may read one ----------------------------------------------------

      test "the submitter can read their own receipt" do
        sign_in @submitter

        get inline_path

        assert_response :success
        assert_equal RECEIPT_BYTES, response.body
      end

      test "another producer cannot read someone else's receipt" do
        sign_in @stranger

        get inline_path

        assert_response :not_found
        assert_not response.body.include?("Acacia Avenue")
      end

      test "the finance team can read any receipt" do
        sign_in @finance_user

        get inline_path

        assert_response :success
        assert_equal RECEIPT_BYTES, response.body
      end

      # A budget owner has to check the receipt to endorse the claim against
      # their budget, and the My Budgets page shows it — so the same rule has to
      # let them fetch it.
      test "a budget owner can read a receipt charged to their budget" do
        sign_in @owner

        get inline_path

        assert_response :success
        assert_equal RECEIPT_BYTES, response.body
      end

      test "a budget owner cannot read a receipt charged to someone else's budget" do
        other_expense = create_reimbursements_expense(
          person: @submitter_person, budget: create_reimbursements_budget(name: "Not theirs"), receipt: false
        )
        attach_test_receipt(other_expense, filename: "other.pdf", bytes: RECEIPT_BYTES)
        sign_in @owner

        get other_expense.receipts.first.url

        assert_response :not_found
      end

      # 404 rather than 403 throughout: "no such receipt" doesn't confirm which
      # claims exist to someone probing for them.
      test "backend access alone is not enough" do
        sign_in @backend_only_user

        get inline_path

        assert_response :not_found
        assert_not response.body.include?("Acacia Avenue")
      end

      # --- Scoping -------------------------------------------------------------

      # The receipt id is only ever resolved WITHIN the claim in the URL, so
      # pairing your own claim's id with someone else's receipt finds nothing.
      test "a receipt id is not honoured against a different claim" do
        mine = create_reimbursements_expense(person: @submitter_person, budget: @budget, receipt: false)
        attach_test_receipt(mine, filename: "mine.pdf", bytes: "%PDF-1.4 mine")
        sign_in @submitter

        get inline_admin_reimbursements_expense_receipt_path(mine.record_id, @receipt.attachment_id)

        assert_response :not_found
      end

      # --- How it is served ----------------------------------------------------

      test "the download URL sends the file as an attachment, the inline one for viewing" do
        sign_in @submitter

        get download_path
        assert_response :success
        assert_match(/^attachment/, response.headers["Content-Disposition"])
        assert_match "receipt.pdf", response.headers["Content-Disposition"]

        get inline_path
        assert_match(/^inline/, response.headers["Content-Disposition"])
        assert_equal "application/pdf", response.media_type
      end

      # A receipt is private to the people checked above, so no shared cache
      # anywhere between here and them may keep a copy.
      test "a served receipt is never marked publicly cacheable" do
        sign_in @submitter

        get inline_path

        assert_no_match(/public/, response.headers["Cache-Control"].to_s)
        assert_match(/private/, response.headers["Cache-Control"].to_s)
      end

      # Chrome's built-in PDF viewer asks for byte ranges; the iframe in the
      # receipt viewer is that viewer.
      test "byte-range requests are honoured for the in-page PDF viewer" do
        sign_in @submitter

        get inline_path, headers: { "Range" => "bytes=0-7" }

        assert_response :partial_content
        assert_equal "%PDF-1.4", response.body
      end

      test "an image receipt gets a thumbnail, served through the same gate" do
        expense = create_reimbursements_expense(person: @submitter_person, budget: @budget, receipt: false)
        expense.receipt_files.attach(
          io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/renderable_receipt.png"))),
          filename: "receipt.png", content_type: "image/png"
        )
        thumbnail_path = expense.reload.receipts.first.thumbnail_url
        assert thumbnail_path.present?, "an image receipt should offer a thumbnail"

        get thumbnail_path
        assert_redirected_to new_user_session_path, "the thumbnail must be gated too"

        sign_in @submitter
        get thumbnail_path
        assert_response :success
      end
    end
  end
end
