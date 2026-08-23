module Admin
  module Reimbursements
    ##
    # The receipt bytes, served by the app so that the permission gating a claim
    # gates its receipt too.
    #
    # Receipts used to be linked over ActiveStorage's own routes, which Rails
    # documents plainly: "All Active Storage controllers are publicly accessible
    # by default. The generated URLs are hard to guess, but permanent by
    # design." A receipt here is a photograph of a till receipt or a supplier's
    # invoice — someone's home address, often their name and card digits — so a
    # link that works forever, for anyone who comes by it, signed in or not, is
    # the wrong shape. Rails' own answer to that is this: an authenticated
    # controller. The blob's signed id is no longer emitted anywhere, so there
    # is no longer a permanent token to leak (see Expense.wrap_receipt).
    #
    # Streamed rather than redirected to the storage host, for three reasons:
    # the in-page viewer's <img>/<iframe> must stay same-origin under the app's
    # CSP; a redirect would hand the browser a presigned URL that outlives the
    # check we just made; and byte-range requests keep the browser's native PDF
    # viewer happy. Receipts are capped at 5 MB (ExpenseForm::MAX_RECEIPT_BYTES)
    # and the audience is a handful of people, so proxying costs little.
    class ReceiptFilesController < BaseController
      include ActiveStorage::Streaming

      # BaseController's producer gate is too narrow here: finance and budget
      # owners both legitimately read receipts, and a finance user need not hold
      # the producer portal permission at all. #authorize_receipt! is the union.
      skip_before_action :authorize_reimbursements!
      before_action :authorize_receipt!

      THUMBNAIL_LIMIT = [ 512, 512 ].freeze

      def inline = stream_receipt(disposition: "inline")

      def download = stream_receipt(disposition: "attachment")

      def thumbnail
        representation = @file.representation(resize_to_limit: THUMBNAIL_LIMIT).processed
        serve { send_blob_stream representation, disposition: "inline" }
      rescue StandardError => e
        # A malformed PDF only fails when its first page is actually rendered,
        # long after a successful upload. The receipt viewer already falls back
        # to a document icon when a thumbnail doesn't load, so 404 into that
        # rather than turning a cosmetic preview into an error page.
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

      # Cached, but PRIVATELY: a receipt is readable only by the few people
      # #visible_to_current_user? admits, so no shared cache between here and
      # them may keep a copy. (ActiveStorage's own proxy sets public, which is
      # right for the world-readable files it assumes and wrong for these.)
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

      # The three places a receipt is already shown on screen, and no more: the
      # finance surfaces (Review, expense edit, exports), the submitter's own
      # claim pages, and a budget owner's My Budgets queue — where checking the
      # receipt is the whole point of the endorsement they are being asked for.
      #
      # Not visible reads as "no such receipt" rather than "forbidden", so a
      # 404 doesn't confirm which claims exist to someone probing for them.
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
