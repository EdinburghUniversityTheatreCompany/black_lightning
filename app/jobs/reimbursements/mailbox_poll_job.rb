module Reimbursements
  # Polls each cost centre's receive mailbox (every 5 minutes) and turns receipt emails into
  # blank DRAFT expenses the sender completes in the portal. Unknown and automated senders,
  # and messages with no usable attachment, are filed in Rejected.
  #
  # Before the expense exists, a failed message is left unread and retried next cycle. After
  # it exists, mark-read is the idempotency commit point (unread_messages never re-fetches a
  # read message), so it runs before the best-effort attach/reply/move; a mark-read failure
  # is the one duplicate-risk case and is flagged to Honeybadger.
  # Graph credential failures alert the IT subcommittee, deduped to once a day.
  class MailboxPollJob < Reimbursements::ApplicationJob
    queue_as :default
    # Must outlive a multi-mailbox poll, or a second run gets past the single-flight guard.
    limits_concurrency key: "reimbursements_mailbox_poll", duration: 10.minutes

    AUTOMATED_SENDER = /mailer-daemon|postmaster|no-?reply|do-?not-?reply/i
    # Caps a spoofed sender minting unbounded drafts or starving the PAGE_SIZE page; set well
    # above any real daily volume.
    MAX_MESSAGES_PER_SENDER_PER_DAY = 30

    # Test seam. Takes the cost centre so each is polled on its own receive mailbox.
    class_attribute :mailbox_builder,
                    default: ->(cost_centre) { ::Graph::MailboxClient.new(mailbox: cost_centre.receive_mailbox) }

    # The People registry is shared, so sender lookups work whichever mailbox a receipt came to.
    def perform
      unless Settings.outbound_enabled?
        Rails.logger.info("Reimbursements mailbox poll skipped: outbound disabled in #{Rails.env}")
        return
      end
      unless Settings.mailbox_configured?
        Rails.logger.info("Reimbursements mailbox poll skipped: Graph credentials not configured")
        return
      end

      CostCentre.all.each { |cost_centre| poll_cost_centre(cost_centre) }
    rescue GraphAuth::AuthError => e
      GraphAuthAlert.notify(e, source: "reimbursements_mailbox_poll")
    end

    private

    attr_reader :mailbox

    # Only AuthError re-raises: it is global (one Entra credential for every mailbox). Any other
    # failure must not stop the other centres' polls.
    def poll_cost_centre(cost_centre)
      @current_cost_centre = cost_centre
      @mailbox = mailbox_builder.call(cost_centre)
      @mailbox.unread_messages.each { |message| process(message) }
    rescue GraphAuth::AuthError
      raise
    rescue => e
      log_and_notify("Reimbursements mailbox poll failed for #{cost_centre.key}: #{e.message}", e,
                     context: { source: "reimbursements_mailbox_poll", cost_centre: cost_centre.key })
    end

    def process(message)
      return handle_automated_sender(message) if automated_sender?(message)

      person = store.person_by_email(message.from_address)
      return handle_unknown_sender(message) if person.nil?
      return handle_rate_limited_sender(message) if sender_over_daily_limit?(message)

      receipts = usable_receipts(message)
      return handle_missing_receipt(message, person) if receipts.empty?

      create_expense(message, person, receipts)
    rescue GraphAuth::AuthError
      raise
    rescue => e
      log_and_notify("Reimbursements poll failed for message #{message.id}: #{e.message}", e,
                     context: { message_id: message.id, from: message.from_address })
      # Leave the message unread; the next poll cycle retries it.
    end

    # Counted once per message id, so a message retried after a later failure does not inflate
    # the sender's tally.
    def sender_over_daily_limit?(message)
      count_key = "reimbursements/mailbox-sender-count/#{message.from_address}/#{Date.current}"
      counted_key = "reimbursements/mailbox-sender-counted/#{message.id}"
      count = Rails.cache.fetch(counted_key, expires_in: 1.day) do
        Rails.cache.increment(count_key, 1, expires_in: 1.day)
      end
      count.to_i > MAX_MESSAGES_PER_SENDER_PER_DAY
    end

    # A reply to a bounce or auto-reply would bounce again and ping-pong every cycle.
    def automated_sender?(message)
      message.from_address.blank? ||
        message.from_address.match?(AUTOMATED_SENDER) ||
        message.from_address.casecmp?(@current_cost_centre.receive_mailbox)
    end

    def usable_receipts(message)
      # Always fetch: Graph reports hasAttachments false when the only image is pasted inline.
      mailbox.attachments(message.id).filter_map do |attachment|
        # A raise here would leave the message unread and reprocessed for ever, so skip it.
        next if attachment[:bytes].blank?

        # Size, real content type (Marcel, not the declared type, which is as spoofable as a
        # browser upload's) and HEIC-to-JPEG conversion happen here. ReceiptIntake never raises:
        # an unreadable photo falls through to the "attach the receipt" reply.
        receipt = ReceiptIntake.from_bytes(bytes: attachment[:bytes], filename: attachment[:filename],
                                           declared_type: attachment[:content_type])
        next log_unusable(message, attachment, receipt) unless receipt.ok?

        receipt.to_attachment
      end
    end

    # Returns nil so filter_map drops the attachment.
    def log_unusable(message, attachment, receipt)
      Rails.logger.info("Reimbursements mailbox: skipping attachment #{attachment[:filename].inspect} " \
                        "on message #{message.id}: #{receipt.error}")
      nil
    end

    def handle_automated_sender(message)
      mailbox.mark_read_and_move(message.id, :rejected)
    end

    def handle_unknown_sender(message)
      mailbox.reply(message.id, html: unknown_sender_html)
      mailbox.mark_read_and_move(message.id, :rejected)
    end

    def handle_missing_receipt(message, person)
      mailbox.reply(message.id, html: missing_receipt_html(person))
      mailbox.mark_read_and_move(message.id, :rejected)
    end

    def handle_rate_limited_sender(message)
      Rails.logger.warn("Reimbursements mailbox: #{message.from_address} exceeded the daily " \
                        "message limit — message #{message.id} rejected")
      mailbox.reply(message.id, html: rate_limited_html)
      mailbox.mark_read_and_move(message.id, :rejected)
    end

    def create_expense(message, person, receipts)
      # A previous cycle may have created the expense and died before marking read: finish
      # that message rather than mint a duplicate.
      if (existing = store.expense_for_source_message(message.id))
        handle_already_processed(message, existing, receipts)
        return
      end

      expense = store.create_expense!(expense_attrs(message, person))
      finalise_created(message, expense, receipts)
    end

    # Mark read FIRST (the idempotency commit point; a failure there is the duplicate-risk
    # case). Attach and reply are separate best-effort steps so an attach failure cannot skip
    # the reply. The move to Processed is gated on attach, so a partly attached draft stays
    # visible in the Inbox.
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

    # The expense exists from an earlier cycle that may have died after the create. Reply only
    # if something was attached now: otherwise that cycle most likely replied already.
    def handle_already_processed(message, expense, receipts)
      Rails.logger.info("Reimbursements mailbox: message #{message.id} already created expense " \
                        "#{expense.record_id}; finishing without a duplicate")
      mark_read_or_flag_duplicate(message, expense) or return

      missing = missing_receipts(expense, receipts)
      attached = missing.empty? || best_effort(message, expense, "receipt attach") do
        missing.each do |receipt|
          store.attach_receipt!(expense.record_id, filename: receipt[:filename],
                                                   content_type: receipt[:content_type],
                                                   bytes: receipt[:bytes])
        end
      end
      if missing.any? && attached
        best_effort(message, expense, "reply") { mailbox.reply(message.id, html: created_html(expense)) }
      end
      best_effort(message, expense, "move to Processed") { mailbox.move(message.id, :processed) } if attached
    end

    # Receipts not yet on the expense, matched by filename and byte size.
    def missing_receipts(expense, receipts)
      existing = expense.receipt_files.map { |file| [ file.filename.to_s, file.byte_size ] }
      receipts.reject { |receipt| existing.include?([ receipt[:filename], receipt[:bytes].bytesize ]) }
    end

    # True on success. On failure the message is still unread and the next poll may mint a
    # duplicate: flag it (duplicate_risk) and skip the reply/move.
    def mark_read_or_flag_duplicate(message, expense)
      mailbox.mark_read(message.id)
      true
    rescue GraphAuth::AuthError
      raise
    rescue => e
      log_and_notify(
        "Reimbursements could not mark message #{message.id} read after creating expense " \
        "#{expense.record_id}; it may be re-processed into a duplicate: #{e.message}", e,
        context: { message_id: message.id, expense_record_id: expense.record_id, duplicate_risk: true }
      )
      false
    end

    # Failures are logged and reported, never raised (the message is already read), except
    # AuthError. Returns false on a swallowed failure so a later step can be gated on it.
    def best_effort(message, expense, description)
      yield
      true
    rescue GraphAuth::AuthError
      raise
    rescue => e
      log_and_notify("Reimbursements #{description} failed for #{message.id}: #{e.message}", e,
                     context: { message_id: message.id, expense_record_id: expense.record_id })
      false
    end

    # A blank DRAFT: only the subject (as description) is known. The reply asks the sender to
    # complete and submit it, so review only sees confirmed claims.
    def expense_attrs(message, person)
      {
        person_record_id: person.record_id,
        # The idempotency stamp: a later poll finds this expense by it.
        source_message_id: message.id,
        status: Status::DRAFT,
        description: message.subject.presence
      }.compact
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

    # Replies are in the name of the cost centre whose mailbox received the message.
    def sign_off
      "#{@current_cost_centre.name} finance (automated reply)"
    end

    def contact_email
      @current_cost_centre.contact_email
    end

    # The replies are raw HTML, so nothing escapes, and first_name is self-service editable.
    # unknown_sender_html and rate_limited_html keep a bare "Hi," on purpose: no matched person.
    def greeting(person)
      ERB::Util.html_escape(GreetingName.for(person))
    end

    def unknown_sender_html
      <<~HTML
        <p>Hi,</p>
        <p>Thanks for your email! Unfortunately this address isn't in our submitter list,
        so we couldn't link your receipt to an account.</p>
        <p>If you're part of #{@current_cost_centre.name}, email from the address you
        registered with, or submit directly through the portal:
        <a href="#{portal_url}">#{portal_url}</a>.</p>
        <p>Questions? Contact #{contact_email}.</p>
        <p>#{sign_off}</p>
      HTML
    end

    def missing_receipt_html(person)
      <<~HTML
        <p>Hi #{greeting(person)},</p>
        <p>Thanks for your email! We found your account, but there was no usable receipt
        attached.</p>
        <p>Please resend with the receipt or invoice as a PDF or photo (JPEG/PNG/WEBP/HEIC,
        up to 5&nbsp;MB). Attaching or pasting the photo into the email both work. Or submit
        through the portal instead: <a href="#{portal_url}">#{portal_url}</a>.</p>
        <p>#{sign_off}</p>
      HTML
    end

    def rate_limited_html
      <<~HTML
        <p>Hi,</p>
        <p>Thanks for your email! We've received an unusually high number of receipts from
        this address today, so this one hasn't been processed automatically.</p>
        <p>Please submit it through the portal instead: <a href="#{portal_url}">#{portal_url}</a>,
        or contact #{contact_email} if this doesn't look right.</p>
        <p>#{sign_off}</p>
      HTML
    end

    def created_html(expense)
      url = edit_url(expense)
      <<~HTML
        <p>Hi #{greeting(expense.person)},</p>
        <p>Thanks for your receipt! We've saved it as a draft expense claim.</p>
        <p><strong>Please check, complete, and submit the claim here:</strong>
        <a href="#{url}">#{url}</a>. Double-check the budget and the payment reference.</p>
        <p>The finance team won't see the claim until you submit it.</p>
        <p>#{sign_off}</p>
      HTML
    end
  end
end
