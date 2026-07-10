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
  # ALWAYS moved to Processed (even when attaching/replying failed) so a
  # transient error can't mint a duplicate expense every 5 minutes.
  # Graph credential failures alert the IT subcommittee, deduped to once/day.
  class MailboxPollJob < ApplicationJob
    queue_as :default
    limits_concurrency key: "reimbursements_mailbox_poll" # overlapping runs would double-process unread mail

    AUTH_ALERT_CACHE_KEY = "reimbursements/auth-failure-alerted".freeze
    SIGN_OFF = "Bedlam Fringe finance (automated reply)".freeze
    AUTOMATED_SENDER = /mailer-daemon|postmaster|no-?reply|do-?not-?reply/i

    # Injection seams for tests (no mocking library in this suite).
    class_attribute :mailbox_builder, default: -> { MailboxClient.new }
    class_attribute :store_builder, default: -> { Store.new }
    class_attribute :extractor_builder, default: -> { Extractor.new }

    def perform
      unless Settings.mailbox_configured?
        Rails.logger.info("Reimbursements mailbox poll skipped: Graph credentials not configured")
        return
      end

      mailbox.unread_messages.each { |message| process(message) }
    rescue MailboxClient::AuthError => e
      alert_auth_failure(e)
    end

    private

    def mailbox
      @mailbox ||= mailbox_builder.call
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
        message.from_address.casecmp?(CostCentre.default.mailbox)
    end

    def usable_receipts(message)
      # Always fetch — Graph reports hasAttachments: false for messages whose
      # only image is pasted inline, which is a perfectly normal way to send
      # a receipt. All attachments and inline images count as receipts.
      mailbox.attachments(message.id).select do |attachment|
        ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(attachment[:content_type]) &&
          attachment[:bytes].bytesize <= ExpenseForm::MAX_RECEIPT_BYTES
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
      begin
        receipts.each do |receipt|
          store.attach_receipt!(expense.record_id, filename: receipt[:filename],
                                                   content_type: receipt[:content_type],
                                                   bytes: receipt[:bytes])
        end
        mailbox.reply(message.id, html: created_html(expense))
      rescue MailboxClient::AuthError
        raise
      rescue => e
        # The expense exists: retrying the whole message would duplicate it,
        # so log loudly and still move the message out of the inbox.
        Rails.logger.error("Reimbursements post-create step failed for #{message.id}: #{e.message}")
        Honeybadger.notify(e, context: { message_id: message.id, expense_record_id: expense.record_id })
      end
      mailbox.mark_read_and_move(message.id, :processed)
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
