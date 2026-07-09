module Reimbursements
  ##
  # Polls the shared reimbursements mailbox (every 5 minutes via Solid Queue)
  # and turns receipt emails into Pending expenses:
  #
  # - unknown sender            -> "address not recognised" reply, Rejected folder
  # - no usable attachment      -> "please attach the receipt" reply, Rejected folder
  # - known sender + attachment -> Gemini-extracted Pending expense (blanks
  #   where unsure), receipts attached, reply with a portal link, Processed
  #
  # A message is only moved out of the inbox after its reply is sent (the move
  # is the commit point), so failures leave it unread for the next cycle.
  # Graph credential failures alert the IT subcommittee, deduped to once/day.
  class MailboxPollJob < ApplicationJob
    queue_as :default

    AUTH_ALERT_CACHE_KEY = "reimbursements/auth-failure-alerted".freeze

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

    def process(message)
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

    # Always fetch — Graph reports hasAttachments: false for messages whose
    # only image is pasted inline, which is a perfectly normal way to send a
    # receipt (MailboxClient applies a size gate to inline images).
    def usable_receipts(message)
      mailbox.attachments(message.id).select do |attachment|
        ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(attachment[:content_type]) &&
          attachment[:bytes].bytesize <= ExpenseForm::MAX_RECEIPT_BYTES
      end
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
      extraction = extractor_builder.call.extract(
        receipts: receipts,
        budgets: store.active_budgets,
        context: "Email subject: #{message.subject}\n\n#{message.body_text}"
      )

      expense = store.create_expense!(expense_attrs(message, person, extraction))
      receipts.each do |receipt|
        store.attach_receipt!(expense.record_id, filename: receipt[:filename],
                                                 content_type: receipt[:content_type],
                                                 bytes: receipt[:bytes])
      end
      mailbox.reply(message.id, html: created_html(expense))
      mailbox.mark_read_and_move(message.id, :processed)
    end

    # Everything the extraction confidently knows, blanks elsewhere — the
    # reply asks the submitter to complete the claim in the portal. Extraction
    # failing entirely still creates the expense (receipt + subject only).
    def expense_attrs(message, person, extraction)
      excl_vat = if extraction.vat_itemised && extraction.total_amount && extraction.vat_amount
        extraction.total_amount - extraction.vat_amount
      end
      {
        person_record_id: person.record_id,
        status: Status::PENDING,
        description: extraction.suggested_description || message.subject.presence,
        amount: extraction.total_amount,
        amount_excl_vat: excl_vat,
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
        <p>Thanks for your email — but this address isn't in our submitter list, so we
        couldn't link your receipt to an account.</p>
        <p>If you're part of Bedlam Fringe, either email from the address you registered
        with, or submit directly through the portal:
        <a href="#{portal_url}">#{portal_url}</a>.</p>
        <p>Questions? Contact finance@bedlamfringe.co.uk.</p>
        <p>— Bedlam Fringe finance (automated)</p>
      HTML
    end

    def missing_receipt_html
      <<~HTML
        <p>Thanks — we found your account, but there was no usable receipt attached.</p>
        <p>Please resend with the receipt or invoice attached as a PDF or photo
        (JPEG/PNG/WEBP, up to 5&nbsp;MB), or submit through the portal:
        <a href="#{portal_url}">#{portal_url}</a>.</p>
        <p>— Bedlam Fringe finance (automated)</p>
      HTML
    end

    def created_html(expense)
      url = edit_url(expense)
      <<~HTML
        <p>Thanks — we've started an expense claim from your receipt.</p>
        <p><strong>Please check and complete it here:</strong>
        <a href="#{url}">#{url}</a> — especially the budget and payment reference.</p>
        <p>It goes to the finance team for review once you've confirmed the details.</p>
        <p>— Bedlam Fringe finance (automated)</p>
      HTML
    end
  end
end
