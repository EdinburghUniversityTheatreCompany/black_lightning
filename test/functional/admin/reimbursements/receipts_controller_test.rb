require "test_helper"

module Admin
  module Reimbursements
    class ReceiptsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        @user = users(:member)
        grant_producer_permission(@user)
        @person = create_reimbursements_person(email: @user.email)
        @other_person = create_reimbursements_person(name: "Other Person", email: "other@example.com")
        @budget = create_reimbursements_budget
        @expense = expense_with_two_receipts(person: @person)
        @other_expense = expense_with_two_receipts(person: @other_person)
        sign_in @user
      end

      def expense_with_two_receipts(person:)
        expense = create_reimbursements_expense(person: person, budget: @budget, receipt: false)
        attach_test_receipt(expense, filename: "old.pdf")
        attach_test_receipt(expense, filename: "new.pdf")
        expense
      end

      # The blob id (Attachment#attachment_id), NOT the signed id, which is a bearer
      # token for ActiveStorage's unauthenticated routes.
      def receipt_id(expense, filename)
        expense.receipt_files.reload.find { |file| file.filename.to_s == filename }.blob_id.to_s
      end

      test "removes a receipt from an own pending expense" do
        delete :destroy, params: { expense_id: @expense.record_id, id: receipt_id(@expense, "old.pdf") }

        assert_redirected_to edit_admin_reimbursements_expense_path(@expense.record_id)
        assert_equal [ "new.pdf" ], @expense.reload.receipt_files.map { |f| f.filename.to_s }
      end

      test "refuses to remove the last receipt" do
        expense = create_reimbursements_expense(person: @person, budget: @budget) # one receipt.pdf

        delete :destroy, params: { expense_id: expense.record_id, id: receipt_id(expense, "receipt.pdf") }

        assert_redirected_to edit_admin_reimbursements_expense_path(expense.record_id)
        assert_match(/last receipt/, flash[:alert])
        assert_equal 1, expense.reload.receipt_files.count, "the receipt was not removed"
      end

      test "destroy as turbo stream replaces the gallery" do
        removed_id = receipt_id(@expense, "old.pdf")
        survivor_id = receipt_id(@expense, "new.pdf")

        delete :destroy, params: { expense_id: @expense.record_id, id: removed_id },
                         format: :turbo_stream

        assert_response :success
        assert_includes response.body, 'turbo-stream action="replace" target="receipts-gallery"'
        # The survivor's remove-control URL renders, the removed receipt's doesn't.
        assert_includes response.body, "receipts/#{survivor_id}"
        assert_not_includes response.body, "receipts/#{removed_id}"
      end

      def receipt_upload = fixture_file_upload("reimbursements_receipt.pdf", "application/pdf")

      test "create attaches uploads and streams the gallery back" do
        assert_difference -> { @expense.receipt_files.count }, 1 do
          post :create, params: { expense_id: @expense.record_id, receipts: [ receipt_upload ] },
                        format: :turbo_stream
        end

        assert_response :success
        assert_includes response.body, 'turbo-stream action="replace" target="receipts-gallery"'
      end

      test "create rejects unusable files with an inline error" do
        # An executable named .pdf and declared as one: rejection must be proved by
        # the real bytes, not the declared type.
        disguised = fixture_file_upload("disguised_executable.pdf", "application/pdf")

        assert_no_difference -> { @expense.receipt_files.count } do
          post :create, params: { expense_id: @expense.record_id, receipts: [ disguised ] },
                        format: :turbo_stream
        end

        assert_response :success
        assert_includes response.body, "must be a PDF or a photo"
      end

      # The gallery converts too: an iPhone photo added to a claim lands as a JPEG.
      test "create converts a HEIC photo to JPEG on the way in" do
        post :create, params: { expense_id: @expense.record_id,
                                receipts: [ fixture_file_upload("reimbursements_receipt.heic", "image/heic") ] },
                      format: :turbo_stream

        receipt = @expense.receipt_files.reload.last
        assert_equal "image/jpeg", receipt.content_type
        assert_equal "reimbursements_receipt.jpg", receipt.filename.to_s
      end

      test "create falls back to a redirect for html" do
        assert_difference -> { @expense.receipt_files.count }, 1 do
          post :create, params: { expense_id: @expense.record_id, receipts: [ receipt_upload ] }
        end

        assert_redirected_to edit_admin_reimbursements_expense_path(@expense.record_id)
      end

      test "another person's expense 404s for both adding and removing a receipt" do
        delete :destroy, params: { expense_id: @other_expense.record_id, id: receipt_id(@other_expense, "old.pdf") }
        assert_response :not_found
        assert_equal 2, @other_expense.reload.receipt_files.count

        post :create, params: { expense_id: @other_expense.record_id, receipts: [ receipt_upload ] }
        assert_response :not_found
        assert_equal 2, @other_expense.reload.receipt_files.count
      end
    end
  end
end
