module Reimbursements
  ##
  # Polls the shared reimbursements mailbox (every 5 minutes via Solid Queue)
  # and turns receipt emails into DRAFT expenses the sender then completes
  # and submits in the portal:
  #
  # - unknown sender            -> "address not recognised" reply, Rejected folder
  # - automated sender          -> no reply (loop guard), Rejected folder
  # - no usable attachment      -> "please attach the receipt" reply, Rejected folder
  # - known sender + attachment -> Gemini-extracted Draft expense (blanks
  #   where unsure), receipts attached, reply with a portal link, Processed
  #
  # Failure handling: before the expense exists, a message is simply left
  # unread and retried next cycle. After the expense exists, the message is
  # marked READ as the guaranteed idempotency step (unread_messages filters on
  # unread, so a read message is never re-fetched) before the best-effort
  # attach/reply/move — so a transient error there can't mint a duplicate
  # expense every 5 minutes. If the mark-read step itself fails after the
  # expense was created, that's the one duplicate-risk case, so it's flagged to
  # Honeybadger rather than silently swallowed.
  # Graph credential failures alert the IT subcommittee, deduped to once/day.
  class MailboxPollJob < ApplicationJob
    queue_as :default
    limits_concurrency key: "reimbursements_mailbox_poll" # overlapping runs would double-process unread mail

    AUTH_ALERT_CACHE_KEY = "reimbursements/auth-failure-alerted".freeze
    SIGN_OFF = "Bedlam Fringe finance (automated reply)".freeze
    AUTOMATED_SENDER = /mailer-daemon|postmaster|no-?reply|do-?not-?reply/i

    # Injection seams for tests (no mocking library in this suite). The mailbox
    # builder takes the cost centre so each is polled on its OWN receive mailbox.
    class_attribute :mailbox_builder,
                    default: ->(cost_centre) { MailboxClient.new(mailbox: cost_centre.receive_mailbox) }
    class_attribute :store_builder, default: -> { Store.new }
    class_attribute :extractor_builder, default: -> { Extractor.new }

    # Every cost centre has its own receive mailbox (Fringe today, termtime next),
    # so poll each in turn. The People registry is shared across the base, so
    # sender lookups still work regardless of which mailbox a receipt arrived on.
    def perform
      unless Settings.mailbox_configured?
        Rails.logger.info("Reimbursements mailbox poll skipped: Graph credentials not configured")
        return
      end

      CostCentre.all.each { |cost_centre| poll_cost_centre_safely(cost_centre) }
    rescue MailboxClient::AuthError => e
      alert_auth_failure(e)
    end

    private

    # A generic (non-auth) failure listing one cost centre's unread messages
    # — a Graph 5xx, a timeout — must not abort polling every OTHER cost
    # centre's mailbox for the rest of this cycle; only AuthError re-raises,
    # since that's genuinely global (the same Entra credential every cost
    # centre's mailbox client shares) and must still reach the IT alert path.
    def poll_cost_centre_safely(cost_centre)
      poll_cost_centre(cost_centre)
    rescue MailboxClient::AuthError
      raise
    rescue => e
      Rails.logger.error("Reimbursements mailbox poll failed for #{cost_centre.key}: #{e.message}")
      Honeybadger.notify(e, context: { source: "reimbursements_mailbox_poll", cost_centre: cost_centre.key })
    end

    def poll_cost_centre(cost_centre)
      @current_cost_centre = cost_centre
      @mailbox = mailbox_builder.call(cost_centre)
      @mailbox.unread_messages.each { |message| process(message) }
    end

    def mailbox
      @mailbox
    end

    def store
      @store ||= store_builder.call
    end

    def extractor
      @extractor ||= extractor_builder.call
    end

    def process(message)
      return handle_automated_sender(message) if automated_sender?(message)

      person = store.person_by_email(message.from_address)
      return handle_unknown_sender(message) if person.nil?

      receipts = usable_receipts(message)
      return handle_missing_receipt(message) if receipts.empty?

      create_expense(message, person, receipts)
    rescue MailboxClient::AuthError
      raise
    rescue => e
      Rails.logger.error("Reimbursements poll failed for message #{message.id}: #{e.message}")
      Honeybadger.notify(e, context: { message_id: message.id, from: message.from_address })
      # Leave the message unread; the next poll cycle retries it.
    end

    # Bounces (NDRs), out-of-office replies and other automated mail must
    # never get a reply — the reply would bounce again and ping-pong with the
    # remote MTA every poll cycle.
    def automated_sender?(message)
      message.from_address.blank? ||
        message.from_address.match?(AUTOMATED_SENDER) ||
        message.from_address.casecmp?(@current_cost_centre&.receive_mailbox)
    end

    def usable_receipts(message)
      # Always fetch — Graph reports hasAttachments: false for messages whose
      # only image is pasted inline, which is a perfectly normal way to send
      # a receipt. All attachments and inline images count as receipts.
      mailbox.attachments(message.id).select do |attachment|
        bytes = attachment[:bytes]
        # Guard nil/empty bytes: a bad attachment must not raise here (it would
        # leave the message unread and reprocessed forever), just be skipped.
        bytes.present? &&
          ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(attachment[:content_type]) &&
          bytes.bytesize <= ExpenseForm::MAX_RECEIPT_BYTES
      end
    end

    def handle_automated_sender(message)
      mailbox.mark_read_and_move(message.id, :rejected)
    end

    def handle_unknown_sender(message)
      mailbox.reply(message.id, html: unknown_sender_html)
      mailbox.mark_read_and_move(message.id, :rejected)
    end

    def handle_missing_receipt(message)
      mailbox.reply(message.id, html: missing_receipt_html)
      mailbox.mark_read_and_move(message.id, :rejected)
    end

    def create_expense(message, person, receipts)
      extraction = extractor.extract(
        receipts: receipts,
        budgets: store.active_budgets,
        context: "Email subject: #{message.subject}\n\n#{message.body_text}"
      )

      expense = store.create_expense!(expense_attrs(message, person, extraction))
      finalise_created(message, expense, receipts)
    end

    # The expense now exists, so the message must never be re-processed. Mark it
    # read first — the guaranteed idempotency step (unread_messages filters on
    # unread) — then do the best-effort attach/reply/move. A failure of the
    # mark-read step is the one path that risks a duplicate next cycle, so it is
    # surfaced loudly rather than swallowed.
    #
    # Attach and reply are separate best-effort steps (not one combined block)
    # so an attach failure partway through a multi-receipt message can't skip
    # the reply the sender is waiting on. The move to Processed is gated on
    # attach succeeding: a partially-attached draft stays visible in the
    # Inbox as a signal something needs manual follow-up, rather than looking
    # identical to a fully successful run once filed away.
    def finalise_created(message, expense, receipts)
      mark_read_or_flag_duplicate(message, expense) or return

      attached = best_effort(message, expense, "receipt attach") do
        receipts.each do |receipt|
          store.attach_receipt!(expense.record_id, filename: receipt[:filename],
                                                   content_type: receipt[:content_type],
                                                   bytes: receipt[:bytes])
        end
      end
      best_effort(message, expense, "reply") { mailbox.reply(message.id, html: created_html(expense)) }
      best_effort(message, expense, "move to Processed") { mailbox.move(message.id, :processed) } if attached
    end

    # Marks the message read. Returns true on success. On failure the expense
    # already exists but the message is still unread, so the next poll may mint
    # a duplicate: flag it (duplicate_risk) so an operator can check, and skip
    # the follow-up (a still-unread message shouldn't be replied to / moved).
    def mark_read_or_flag_duplicate(message, expense)
      mailbox.mark_read(message.id)
      true
    rescue MailboxClient::AuthError
      raise
    rescue => e
      Rails.logger.error("Reimbursements could not mark message #{message.id} read after " \
                         "creating expense #{expense.record_id}; it may be re-processed into a " \
                         "duplicate: #{e.message}")
      Honeybadger.notify(e, context: { message_id: message.id, expense_record_id: expense.record_id,
                                       duplicate_risk: true })
      false
    end

    # Runs a follow-up step that happens after the expense exists and the
    # message is already read: any failure is logged + reported but never
    # re-raised (the message is safe), except AuthError which aborts the poll to
    # alert on credentials. Returns true on success, false on a swallowed
    # failure, so a caller can gate a later step on this one's success.
    def best_effort(message, expense, description)
      yield
      true
    rescue MailboxClient::AuthError
      raise
    rescue => e
      Rails.logger.error("Reimbursements #{description} failed for #{message.id}: #{e.message}")
      Honeybadger.notify(e, context: { message_id: message.id, expense_record_id: expense.record_id })
      false
    end

    # Everything the extraction confidently knows, blanks elsewhere. The
    # expense lands as a DRAFT: the reply asks the sender to complete and
    # submit it in the portal, so review only ever sees confirmed claims.
    # Extraction failing entirely still creates the draft (receipt + subject).
    def expense_attrs(message, person, extraction)
      {
        person_record_id: person.record_id,
        status: Status::DRAFT,
        description: extraction.suggested_description || message.subject.presence,
        amount: extraction.total_amount,
        amount_excl_vat: extraction.amount_excl_vat,
        budget_record_id: extraction.suggested_budget_record_id,
        payment_reference: extraction.suggested_payment_reference
      }.compact
    end

    def alert_auth_failure(error)
      Honeybadger.notify(error, context: { source: "reimbursements_mailbox_poll" })
      Rails.cache.fetch(AUTH_ALERT_CACHE_KEY, expires_in: 1.day) do
        ReimbursementsMailer.auth_failure(error.message).deliver_now
        true
      end
    end

    def portal_url
      Rails.application.routes.url_helpers.admin_reimbursements_expenses_url(default_url_options)
    end

    def edit_url(expense)
      Rails.application.routes.url_helpers.edit_admin_reimbursements_expense_url(
        expense.record_id, **default_url_options
      )
    end

    def default_url_options
      Rails.application.config.action_mailer.default_url_options || {}
    end

    def unknown_sender_html
      <<~HTML
        <p>Hi,</p>
        <p>Thanks for your email! Unfortunately this address isn't in our submitter list,
        so we couldn't link your receipt to an account.</p>
        <p>If you're part of Bedlam Fringe, email from the address you registered with,
        or submit directly through the portal:
        <a href="#{portal_url}">#{portal_url}</a>.</p>
        <p>Questions? Contact finance@bedlamfringe.co.uk.</p>
        <p>#{SIGN_OFF}</p>
      HTML
    end

    def missing_receipt_html
      <<~HTML
        <p>Hi,</p>
        <p>Thanks for your email! We found your account, but there was no usable receipt
        attached.</p>
        <p>Please resend with the receipt or invoice as a PDF or photo (JPEG/PNG/WEBP, up
        to 5&nbsp;MB). Attaching or pasting the photo into the email both work. Or submit
        through the portal instead: <a href="#{portal_url}">#{portal_url}</a>.</p>
        <p>#{SIGN_OFF}</p>
      HTML
    end

    def created_html(expense)
      url = edit_url(expense)
      <<~HTML
        <p>Hi,</p>
        <p>Thanks for your receipt! We've saved it as a draft expense claim.</p>
        <p><strong>Please check, complete, and submit the claim here:</strong>
        <a href="#{url}">#{url}</a>. Double-check the budget and the payment reference.</p>
        <p>The finance team won't see the claim until you submit it.</p>
        <p>#{SIGN_OFF}</p>
      HTML
    end
  end
end
