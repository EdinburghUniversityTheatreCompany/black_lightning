require "test_helper"

module Admin
  module Reimbursements
    class ReceiptsControllerTest < ActionController::TestCase
      include ReimbursementsTestHelpers

      setup do
        producer = Role.create!(name: "Producer")
        producer.permissions << Permission.create(action: "access", subject_class: "reimbursements")
        users(:member).add_role("Producer")
        @user = users(:member)
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

      # The route/param identifier of an attached receipt: the blob signed id
      # the Attachment wrapper exposes as attachment_id.
      def receipt_id(expense, filename)
        expense.receipt_files.reload.find { |file| file.filename.to_s == filename }.signed_id
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

      test "404s for another person's expense" do
        delete :destroy, params: { expense_id: @other_expense.record_id,
                                   id: receipt_id(@other_expense, "old.pdf") }

        assert_response :not_found
        assert_equal 2, @other_expense.reload.receipt_files.count
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

      def receipt_upload(content_type = "application/pdf")
        fixture_file_upload("reimbursements_receipt.pdf", content_type)
      end

      test "create attaches uploads and streams the gallery back" do
        assert_difference -> { @expense.receipt_files.count }, 1 do
          post :create, params: { expense_id: @expense.record_id, receipts: [ receipt_upload ] },
                        format: :turbo_stream
        end

        assert_response :success
        assert_includes response.body, 'turbo-stream action="replace" target="receipts-gallery"'
      end

      test "create rejects unusable files with an inline error" do
        # An executable disguised with a .pdf filename and declared content_type:
        # content-type filtering is based on the actual bytes (Marcel), not the
        # declared/filename-implied type, so a mismatched-but-real PDF won't do
        # here to prove rejection.
        disguised = fixture_file_upload("disguised_executable.pdf", "application/pdf")

        assert_no_difference -> { @expense.receipt_files.count } do
          post :create, params: { expense_id: @expense.record_id, receipts: [ disguised ] },
                        format: :turbo_stream
        end

        assert_response :success
        assert_includes response.body, "must be a PDF or a photo"
      end

      test "create falls back to a redirect for html" do
        assert_difference -> { @expense.receipt_files.count }, 1 do
          post :create, params: { expense_id: @expense.record_id, receipts: [ receipt_upload ] }
        end

        assert_redirected_to edit_admin_reimbursements_expense_path(@expense.record_id)
      end

      test "create 404s for another person's expense" do
        assert_no_difference -> { @other_expense.receipt_files.count } do
          post :create, params: { expense_id: @other_expense.record_id, receipts: [ receipt_upload ] }
        end

        assert_response :not_found
      end
    end
  end
end
