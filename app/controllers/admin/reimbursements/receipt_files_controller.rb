module Admin
  module Reimbursements
    ##
    # Receipt bytes, served by the app so the permission gating a claim gates its
    # receipt too. NOT over ActiveStorage's routes, which are public and permanent
    # by design, and a receipt carries a home address (Expense.wrap_receipt emits no
    # signed id).
    #
    # Streamed rather than redirected: the viewer's <img>/<iframe> must stay
    # same-origin under the CSP, a presigned URL would outlive the check, and the
    # native PDF viewer wants byte ranges.
    class ReceiptFilesController < BaseController
      include ActiveStorage::Streaming

      # A finance user need not hold the portal permission; #authorize_receipt! is
      # the union.
      skip_before_action :authorize_reimbursements!
      before_action :authorize_receipt!

      THUMBNAIL_LIMIT = [ 512, 512 ].freeze

      def inline = stream_receipt(disposition: "inline")

      def download = stream_receipt(disposition: "attachment")

      def thumbnail
        representation = @file.representation(resize_to_limit: THUMBNAIL_LIMIT).processed
        serve { send_blob_stream representation, disposition: "inline" }
      rescue StandardError => e
        # A malformed PDF only fails when rendered: 404 into the viewer's icon fallback.
        Rails.logger.warn("Reimbursements receipt thumbnail failed for expense " \
                          "#{params[:expense_id]} receipt #{params[:id]}: #{e.class}: #{e.message}")
        head :not_found
      end

      private

      def stream_receipt(disposition:)
        range = request.headers["Range"]
        return serve { send_blob_byte_range_data @file.blob, range, disposition: disposition } if range.present?

        serve do
          response.headers["Accept-Ranges"] = "bytes"
          response.headers["Content-Length"] = @file.blob.byte_size.to_s
          send_blob_stream @file.blob, disposition: disposition
        end
      end

      # PRIVATE caching, so no shared cache keeps a copy (ActiveStorage's proxy
      # sets public).
      def serve
        expires_in 5.minutes, public: false
        yield
      end

      def authorize_receipt!
        expense = store.find_expense!(params[:expense_id])
        raise ActiveRecord::RecordNotFound unless expense && visible_to_current_user?(expense)

        # Resolved WITHIN the claim, never globally: a claim you may read paired with
        # a receipt id from one you may not must find nothing.
        @file = expense.receipt_files.find { |file| file.blob_id.to_s == params[:id] }
        raise ActiveRecord::RecordNotFound unless @file
      end

      # A budget owner is included because checking the receipt is the point of the
      # endorsement. Callers raise RecordNotFound, not 403, so a 404 doesn't confirm
      # which claims exist.
      def visible_to_current_user?(expense)
        return true if can?(:manage, :reimbursements_finance)
        return false unless can?(:access, :reimbursements)

        own_expense?(expense) || ::Reimbursements::OwnerReview.owned_by?(expense, current_person)
      end

      def own_expense?(expense)
        current_person.present? && expense.person&.record_id == current_person.record_id
      end
    end
  end
end
