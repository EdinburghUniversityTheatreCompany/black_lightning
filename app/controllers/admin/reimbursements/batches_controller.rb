module Admin
  module Reimbursements
    ##
    # Build Batch and History. #create enqueues BuildBatchJob (a build can exceed
    # the request timeout) and sends the operator to History; #reopen reverts a
    # batch's expenses to Approved and deletes it so it can be rebuilt.
    class BatchesController < FinanceController
      before_action :require_cost_centre, only: %i[new create]

      # How many follow-up failures History lists before collapsing them.
      INLINE_FAILURE_MESSAGES = 3

      def index
        @title = "Batch history"
        @batches = store.batches_for_cost_centre.sort_by { |batch| batch.date_sent || Date.new(0) }.reverse
        respond_to do |format|
          format.html { load_history }
          format.csv { send_export ::Reimbursements::Exports::Batches, @batches }
        end
      end

      def show
        @batch = find_or_404(:find_batch)
        @expenses = batch_expenses(@batch)
      end

      def new
        assign_new_form
      end

      # The BACS date is validated BEFORE enqueuing: a bad one must never fall
      # back to today, a wrong payment date.
      def create
        bacs_date = parse_bacs_date(params[:bacs_date])
        error = "Enter a valid BACS date (YYYY-MM-DD) before building the batch." if bacs_date.nil?
        error ||= "Enter a valid EUSA recipient email address before building the batch." if invalid_eusa_recipient?
        if error
          assign_new_form
          flash.now[:alert] = error
          return render :new, status: :unprocessable_entity
        end

        # History's trace of this build from the click; the job resolves it by id.
        attempt = ::Reimbursements::BatchAttempt.create!(
          cost_centre: @cost_centre, bacs_date: bacs_date,
          triggered_by_email: current_user.try(:email)
        )
        ::Reimbursements::BuildBatchJob.perform_later(
          cost_centre_key: @cost_centre.key,
          bacs_date: bacs_date.iso8601,
          sender_name: params[:sender_name].presence || default_sender,
          eusa_recipient: params[:eusa_recipient].presence || @cost_centre.eusa_recipient_or_default,
          eusa_subject: params[:eusa_subject].presence,
          eusa_body_html: params[:eusa_body].presence,
          operator_emails: Array(current_user.try(:email)).compact_blank,
          attempt_id: attempt.id
        )
        redirect_to history_path,
                    notice: "Batch is building for #{@cost_centre.name}. Its EUSA draft link will appear " \
                            "here and be emailed to you when ready. Don't rebuild it in the meantime."
      end

      def reopen
        batch = find_or_404(:find_batch)
        linked = batch_expenses(batch)
        paid = linked.select { |expense| expense.status == ::Reimbursements::Status::PAID }
        return blocked_by_paid(paid) if paid.any?

        # Resolved BEFORE the revert: the mailbox is read off the batch's
        # expenses, and the revert unlinks them.
        mailbox = mailbox_holding_draft(batch, draft_mailboxes(linked)) if batch.draft_message_id.present?
        return blocked_by_unconfirmed_draft if batch.draft_message_id.present? && mailbox.nil?

        linked.each { |expense| store.revert_expense_to_approved!(expense.record_id) }
        store.delete_batch!(batch.record_id)

        reverted = "Reverted #{linked.size} #{'expense'.pluralize(linked.size)} to Approved and removed the batch."
        redirect_to history_path, **draft_cleanup_flash(batch, reverted, mailbox)
      end

      # #reopen's probe on its own: is the EUSA draft still unsent? On demand,
      # never on page load: a batch list must not wait on Microsoft.
      def check_draft
        batch = find_or_404(:find_batch)

        if batch.draft_message_id.blank?
          return redirect_to_history(alert: "No EUSA draft was recorded for this batch, so there " \
                                            "is nothing to check. Look in Outlook before rebuilding it.")
        end

        mailbox = mailbox_holding_draft(batch, draft_mailboxes(batch_expenses(batch)))
        if mailbox
          redirect_to_history(notice: "Checked just now: this batch's EUSA draft is still UNSENT in " \
                                      "#{mailbox}. EUSA has not been asked to pay it yet.")
        else
          # draft_message? fails CLOSED: this covers sent, deleted, moved and
          # Graph being down alike, so it must not claim "sent".
          redirect_to_history(alert: "Couldn't confirm this batch's EUSA draft is still unsent. It may " \
                                     "already have been sent, it may have been deleted or moved, or " \
                                     "Graph couldn't be reached. Check Outlook before acting on it.")
        end
      end

      private

      # Back to whichever page the check was made from (History or Detail).
      def redirect_to_history(**flash_args)
        redirect_back fallback_location: history_path, **flash_args
      end

      def history_path
        admin_reimbursements_batches_path(**scope_params)
      end

      def assign_new_form
        @title = "Build batch"
        @expenses = approved_expenses
        @total = @expenses.sum { |expense| expense.amount || 0 }
        @bacs_date = Date.current
        @sender_name = default_sender
        @eusa_recipient = @cost_centre.eusa_recipient_or_default
        @default_email = ::Reimbursements::EusaEmailComposer.new.compose(
          expenses: @expenses, bacs_date: @bacs_date, sender_name: @sender_name, cost_centre: @cost_centre
        )
      end

      # The revert has already happened and stands, so a failed draft delete
      # (or no stored draft id) only adds a delete-it-by-hand warning.
      def draft_cleanup_flash(batch, reverted, mailbox)
        if batch.draft_message_id.present?
          begin
            graph.delete_message(mailbox: mailbox, message_id: batch.draft_message_id)
            return { notice: "#{reverted} The old EUSA draft in Outlook has been deleted." }
          rescue StandardError => e
            log_and_notify("Reopen: failed to delete EUSA draft #{batch.draft_message_id} — #{e.message}", e,
                           context: { source: "reimbursements_reopen_draft_delete", batch: batch.record_id })
          end
        end

        { notice: reverted,
          alert: "Delete the old EUSA draft in Outlook manually before sending the rebuilt one." }
      end

      # Where the draft might be, best guess first. A batch has no cost-centre
      # column, so its centre is read off its expenses: a GUESS for batches built
      # before single-centre builds, which all drafted into the default mailbox.
      # A LIST because draft_message? fails CLOSED, so one wrong guess would read
      # as permanently "already sent". Unplaced claims say nothing, so are skipped.
      def draft_mailboxes(linked_expenses)
        ids = linked_expenses.filter_map(&:cost_centre_id).uniq
        derived = store.cost_centres.find { |centre| centre.id == ids.first } if ids.one?
        [ derived, ::Reimbursements::CostCentre.default ]
          .compact.filter_map { |centre| centre.send_mailbox.presence }.uniq
      end

      # The first candidate still holding the draft; nil is the "may already
      # have been sent" refusal. Reopen must never revert a batch whose draft
      # was already sent, and only Graph can tell.
      def mailbox_holding_draft(batch, mailboxes)
        mailboxes.find { |mailbox| graph.draft_message?(mailbox: mailbox, message_id: batch.draft_message_id) }
      end

      def blocked_by_unconfirmed_draft
        redirect_to history_path,
                    alert: "Can't reopen: the EUSA draft for this batch could not be confirmed as " \
                           "still unsent in Outlook (it may already have been sent, or Graph couldn't " \
                           "be reached). If it was genuinely sent, do not reopen; repair reconciliation " \
                           "manually instead of rebuilding."
      end

      # A batch is ONE centre's submission: the page's ?cost_centre=, else the
      # sole configured one. Never CostCentre.default once a second centre
      # exists: that paid termtime's claims from Fringe's pot.
      def require_cost_centre
        @cost_centre = selected_cost_centre || sole_cost_centre
        return if @cost_centre

        # ASK rather than bounce: the sidebar's link names no centre when there is no home centre
        # or All is chosen, and a redirect would make Build Batch unreachable from where most
        # operators start.
        if selectable_cost_centres.any?
          @title = "Build batch"
          return render :choose_cost_centre
        end

        redirect_to history_path,
                    alert: "No cost centre configured. Seed one before building a batch."
      end

      def sole_cost_centre
        selectable_cost_centres.one? ? selectable_cost_centres.first : nil
      end

      # The money path's OWNERSHIP rule, not the screens' lenient filter, so an
      # unplaced claim cannot reach two drafts. BuildBatchJob asks the same.
      def approved_expenses
        store.expenses_owned_by_cost_centre(@cost_centre)
             .select { |expense| expense.status == ::Reimbursements::Status::APPROVED }
      end

      # What only the HTML page needs; the CSV gets its figures from the exporter.
      def load_history
        @expenses_by_batch = processed_expenses.group_by(&:batch_id)
        attempts = ::Reimbursements::BatchAttempt.needing_attention
                                                 .where(created_at: 7.days.ago..)
                                                 .includes(:cost_centre).recent_first
        # Every attempt has a cost centre, so this filter needs no leniency.
        attempts = attempts.where(cost_centre_id: selected_cost_centre.id) if selected_cost_centre
        @batch_attempts = attempts
      end

      def processed_expenses
        store.expenses.select { |expense| expense.batch_id.present? }
      end

      def batch_expenses(batch)
        store.expenses.select { |expense| expense.batch_id == batch.record_id }
      end

      def parse_bacs_date(value)
        Date.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # The override is the draft's only "to" address and is format-checked
      # nowhere else. Blank falls back to the centre's own recipient.
      def invalid_eusa_recipient?
        params[:eusa_recipient].present? && !params[:eusa_recipient].match?(URI::MailTo::EMAIL_REGEXP)
      end

      def default_sender
        current_user.try(:full_name).presence || @cost_centre.finance_sender_name
      end

      def blocked_by_paid(paid)
        numbers = paid.map { |expense| "##{expense.auto_number}" }.join(", ")
        redirect_to history_path,
                    alert: "Can't reopen: #{paid.size} #{'expense'.pluralize(paid.size)} already Paid " \
                           "(#{numbers}). Reconciled payments must not be reverted."
      end
    end
  end
end
