module Admin
  module Reimbursements
    ##
    # Finance-team Build Batch + History.
    #
    # * new / create — preview every Approved expense via its EFFECTIVE payee
    #   (flagging "→ third party" overrides), set the BACS date / EUSA recipient
    #   / signature and edit the EUSA email, then enqueue BuildBatchJob, which
    #   creates the draft in the cost centre's send mailbox, offloads receipts +
    #   the xlsx to SharePoint, records the Batch and marks the expenses Submitted.
    # * index / show — past batches with per-batch totals and links.
    # * reopen — revert a batch's expenses to Approved and delete it so it can be
    #   rebuilt; blocked if any expense is already Paid (reconciled).
    #
    # Build Batch runs in the BACKGROUND (BuildBatchJob): the processor is
    # API-heavy (SharePoint uploads + Graph draft) and can exceed the request
    # timeout, and a concurrency lock on the cost centre stops a double-click
    # double-submitting. The operator is redirected to History and emailed the
    # draft link when it's ready.
    class BatchesController < FinanceController
      before_action :require_cost_centre, only: %i[new create]

      def index
        @title = "Batch history"
        @batches = store.batches_for_cost_centre.sort_by { |batch| batch.date_sent || Date.new(0) }.reverse
        respond_to do |format|
          format.html { load_history }
          # One row per batch, summarising its expenses (Exports::Batches).
          format.csv { send_export ::Reimbursements::Exports::Batches, @batches }
        end
      end

      def show
        @batch = find_or_404(:find_batch)
        @expenses = processed_expenses.select { |expense| expense.batch_id == @batch.record_id }
      end

      def new
        assign_new_form
      end

      # Enqueue the build (BuildBatchJob serialises per cost centre, so a
      # double-click can't double-submit) and send the operator to History; the
      # draft link lands there and in their inbox when the background run finishes.
      #
      # The BACS date is validated BEFORE enqueuing: a blank/malformed date must
      # not silently fall back to today (a wrong payment date), so re-render the
      # form with an error and enqueue nothing.
      def create
        bacs_date = parse_bacs_date(params[:bacs_date])
        if bacs_date.nil?
          assign_new_form
          flash.now[:alert] = "Enter a valid BACS date (YYYY-MM-DD) before building the batch."
          return render :new, status: :unprocessable_entity
        end

        if invalid_eusa_recipient?
          assign_new_form
          flash.now[:alert] = "Enter a valid EUSA recipient email address before building the batch."
          return render :new, status: :unprocessable_entity
        end

        # The attempt row is History's in-app trace of this build — visible
        # from the moment of the click (queued/running), resolved by the job
        # (by id) to completed/failed/nothing_to_build. Without it, a build that
        # dies before the Batch record exists is invisible outside email.
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
        redirect_to admin_reimbursements_batches_path,
                    notice: "Batch is building for #{@cost_centre.name}. Its EUSA draft link will appear " \
                            "here and be emailed to you when ready. Don't rebuild it in the meantime."
      end

      def reopen
        batch = find_or_404(:find_batch)
        linked = processed_expenses.select { |expense| expense.batch_id == batch.record_id }
        paid = linked.select { |expense| expense.status == ::Reimbursements::Status::PAID }
        return blocked_by_paid(paid) if paid.any?

        # Resolved BEFORE the revert: a batch has no cost-centre column of its
        # own, so its mailbox is read off the expenses it holds — and the revert
        # is what unlinks them. Read afterwards, every reopen would fall back to
        # the default centre and look for the draft in the wrong mailbox.
        mailbox = mailbox_holding_draft(batch, draft_mailboxes(linked))
        return blocked_by_unconfirmed_draft if batch.draft_message_id.present? && mailbox.nil?

        linked.each { |expense| store.revert_expense_to_approved!(expense.record_id) }
        store.delete_batch!(batch.record_id)

        reverted = "Reverted #{linked.size} #{'expense'.pluralize(linked.size)} to Approved and removed the batch."
        redirect_to admin_reimbursements_batches_path, **draft_cleanup_flash(batch, reverted, mailbox)
      end

      private

      def assign_new_form
        @title = "Build batch"
        @expenses = approved_expenses
        @total = total(@expenses)
        @bacs_date = Date.current
        @sender_name = default_sender
        @eusa_recipient = @cost_centre.eusa_recipient_or_default
        @default_email = compose_default_email(@bacs_date, @sender_name)
      end

      # Delete the stale EUSA draft this batch created, then build the reopen
      # flash. The revert + batch delete have already happened and must stand, so
      # a Graph failure is rescued (best-effort): the reopen still succeeds, with
      # a warning telling the operator to delete the draft by hand. Falls back to
      # the same manual warning when the batch has no stored draft id.
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

      # Where a batch's EUSA draft might be, best guess first. A Batch carries no
      # cost-centre column, so the centre is read off the expenses it holds —
      # exact for a batch built since Build Batch became single-centre, and a
      # GUESS for anything older.
      #
      # Which is why this is a LIST and not an answer. Every batch built before
      # cost centres existed drafted into the default centre's mailbox whatever
      # its claims say, so a legacy batch holding one placed termtime claim
      # derives "termtime" and would look in a mailbox that never held its
      # draft. GraphClient#draft_message? fails CLOSED, so that mis-guess reads
      # as "already sent — do not reopen", which is untrue and, being derived
      # from stored data, would never stop being untrue. Probing the derived
      # centre and then the default costs one extra Graph read and cannot get
      # stuck.
      #
      # Unplaced claims are dropped from the derivation (rather than falling to
      # the default centre as the money path makes them): they say nothing about
      # where a draft was written, and the default is already the last
      # candidate.
      def draft_mailboxes(linked_expenses)
        ids = linked_expenses.filter_map(&:cost_centre_id).uniq
        derived = ids.one? && store.cost_centres.find { |centre| centre.id == ids.first }
        [ derived, ::Reimbursements::CostCentre.default ]
          .select { |centre| centre.respond_to?(:send_mailbox) }
          .filter_map { |centre| centre.send_mailbox.presence }.uniq
      end

      # The first candidate that still holds this batch's draft, or nil if none
      # does — which is the "it may already have been sent" refusal, now reached
      # only after every mailbox the draft could be in has been asked.
      def mailbox_holding_draft(batch, mailboxes)
        return mailboxes.first if batch.draft_message_id.blank?

        mailboxes.find { |mailbox| confirmed_still_draft?(batch, mailbox) }
      end

      # Reopen must never revert expenses out of a batch whose EUSA draft was
      # already sent — the whole point of "reopen" is to safely rebuild, and a
      # sent draft means the money is already committed. This app has no
      # visibility into the manual "send in Outlook" step by design, so the
      # only way to tell is asking Graph whether the stored message id is
      # still an unsent draft right now.
      def confirmed_still_draft?(batch, mailbox)
        graph.draft_message?(mailbox: mailbox, message_id: batch.draft_message_id)
      end

      def blocked_by_unconfirmed_draft
        redirect_to admin_reimbursements_batches_path,
                    alert: "Can't reopen: the EUSA draft for this batch could not be confirmed as " \
                           "still unsent in Outlook (it may already have been sent, or Graph couldn't " \
                           "be reached). If it was genuinely sent, do not reopen; repair reconciliation " \
                           "manually instead of rebuilding."
      end

      # A batch is ONE cost centre's BACS submission — its spreadsheet, its EUSA
      # draft and its sender mailbox all belong to that centre — so the centre
      # has to be settled before the form is drawn.
      #
      # It comes from the page's own ?cost_centre= selector, falling back to the
      # sole configured centre when there is only one (the state the portal is
      # in today, where there is nothing to choose). It deliberately does NOT
      # fall back to CostCentre.default once a second centre exists: that is
      # order(:id).first, so Build Batch used to put termtime's approved claims
      # into a Fringe batch, paid out of Fringe's pot, from Fringe's mailbox.
      def require_cost_centre
        @cost_centre = selected_cost_centre || sole_cost_centre
        return if @cost_centre

        return render_cost_centre_chooser if selectable_cost_centres.any?

        redirect_to admin_reimbursements_batches_path,
                    alert: "No cost centre configured. Seed one before building a batch."
      end

      def sole_cost_centre
        selectable_cost_centres.one? ? selectable_cost_centres.first : nil
      end

      # ASK, rather than bounce. The sidebar's "Build Batch" entry carries no
      # cost centre and never can — it is one link on every admin page — so with
      # a second centre configured a redirect here would make Build Batch
      # unreachable from the only place most operators start. Each centre is a
      # link into this same action carrying ?cost_centre=, so the form is one
      # click away and the URL still says which pot it is for.
      def render_cost_centre_chooser
        @title = "Build batch"
        render :choose_cost_centre
      end

      # The Approved claims THIS BATCH's cost centre is responsible for paying,
      # never the whole portal's — and read through the money path's OWNERSHIP
      # rule, not the screens' lenient filter, so an unplaced claim belongs to
      # exactly one centre and cannot be built into two drafts. The preview here
      # and BuildBatchJob's own re-selection ask the same question, so what the
      # operator confirms is what gets built.
      def approved_expenses
        store.expenses_owned_by_cost_centre(@cost_centre)
             .select { |expense| expense.status == ::Reimbursements::Status::APPROVED }
      end

      # Submitted + Paid expenses carry a batch link; these populate History.
      # The instance vars only the History page itself needs (the CSV gets its
      # per-batch figures from the exporter).
      def load_history
        @expenses_by_batch = processed_expenses.group_by(&:batch_id)
        # In-flight/failed/no-op builds (and completed-with-warnings) from the
        # last week — a cleanly completed attempt is redundant with its Batch
        # row, but these have no other in-app trace.
        attempts = ::Reimbursements::BatchAttempt.needing_attention
                                                 .where(created_at: 7.days.ago..)
                                                 .includes(:cost_centre).recent_first
        # BatchAttempt carries its own cost_centre_id (NOT NULL), so this one
        # needs no leniency: every attempt row knows which pot it was built for.
        attempts = attempts.where(cost_centre_id: selected_cost_centre.id) if selected_cost_centre
        @batch_attempts = attempts
      end

      def processed_expenses
        store.expenses.select { |expense| expense.batch_id.present? }
      end

      def total(expenses)
        expenses.sum { |expense| expense.amount || 0 }
      end

      # Parse the submitted BACS date, or nil if it's blank/malformed — the
      # caller re-renders the form rather than silently defaulting to today.
      def parse_bacs_date(value)
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # The form's EUSA recipient is free text overriding the cost centre's
      # own (format-validated) configured recipient, passed straight through
      # as the sole "to" address of the EUSA draft — it gets no format check
      # of its own otherwise. Blank is fine (falls back to the cost centre's
      # recipient); only a non-blank, malformed value is rejected.
      def invalid_eusa_recipient?
        params[:eusa_recipient].present? && !params[:eusa_recipient].match?(URI::MailTo::EMAIL_REGEXP)
      end

      def default_sender
        current_user.try(:full_name).presence || @cost_centre.finance_sender_name
      end

      def compose_default_email(bacs_date, sender_name)
        ::Reimbursements::EusaEmailComposer.new.compose(
          expenses: approved_expenses, bacs_date: bacs_date, sender_name: sender_name,
          cost_centre: @cost_centre
        )
      end

      def blocked_by_paid(paid)
        numbers = paid.map { |expense| "##{expense.auto_number}" }.join(", ")
        redirect_to admin_reimbursements_batches_path,
                    alert: "Can't reopen: #{paid.size} #{'expense'.pluralize(paid.size)} already Paid " \
                           "(#{numbers}). Reconciled payments must not be reverted."
      end
    end
  end
end
