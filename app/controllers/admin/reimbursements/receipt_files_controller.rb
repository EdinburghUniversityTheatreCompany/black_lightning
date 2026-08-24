module Admin
  module Reimbursements
    ##
    # The receipt bytes, served by the app so that the permission gating a claim
    # gates its receipt too. NOT over ActiveStorage's own routes, which Rails
    # documents as "publicly accessible by default... hard to guess, but
    # permanent by design" — and a receipt carries a home address. The signed id
    # that unlocks those routes is no longer emitted (see Expense.wrap_receipt).
    #
    # Streamed rather than redirected to the storage host: the viewer's
    # <img>/<iframe> must stay same-origin under the app's CSP, a redirect would
    # hand over a presigned URL outliving the check just made, and byte ranges
    # keep the browser's native PDF viewer happy.
    class ReceiptFilesController < BaseController
      include ActiveStorage::Streaming

      # BaseController's producer gate is too narrow: a finance user need not
      # hold the portal permission at all. #authorize_receipt! is the union.
      skip_before_action :authorize_reimbursements!
      before_action :authorize_receipt!

      THUMBNAIL_LIMIT = [ 512, 512 ].freeze

      def inline = stream_receipt(disposition: "inline")

      def download = stream_receipt(disposition: "attachment")

      def thumbnail
        representation = @file.representation(resize_to_limit: THUMBNAIL_LIMIT).processed
        serve { send_blob_stream representation, disposition: "inline" }
      rescue StandardError => e
        # A malformed PDF only fails when its first page is rendered, long after
        # a successful upload. The viewer already falls back to a document icon
        # when a thumbnail doesn't load, so 404 into that.
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

      # PRIVATE caching: no shared cache may keep a copy. (ActiveStorage's own
      # proxy sets public, right for the world-readable files it assumes.)
      def serve
        expires_in 5.minutes, public: false
        yield
      end

      def authorize_receipt!
        expense = store.find_expense!(params[:expense_id])
        raise ActiveRecord::RecordNotFound unless expense && visible_to_current_user?(expense)

        # Resolved WITHIN the claim, never globally: pairing a claim you may
        # read with a receipt id from one you may not must find nothing.
        @file = expense.receipt_files.find { |file| file.blob_id.to_s == params[:id] }
        raise ActiveRecord::RecordNotFound unless @file
      end

      # The places a receipt is already shown on screen, and no more. A budget
      # owner is here because checking the receipt is the point of the
      # endorsement they are asked for. Not visible raises RecordNotFound rather
      # than denying access, so a 404 doesn't confirm which claims exist.
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
