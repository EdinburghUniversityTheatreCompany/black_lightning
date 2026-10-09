module Reimbursements
  ##
  # One BACS submission: builds the payment documents from each claim's
  # EFFECTIVE payee details, uploads them and the receipts to SharePoint,
  # creates the EUSA draft, records the Batch, marks the expenses Submitted and
  # emails the producers.
  #
  # CARDINAL RULE: expenses are never marked Submitted unless the EUSA draft
  # was created, so a failed draft leaves them Approved and a rebuild is clean.
  # ORPHAN-DRAFT GUARD: once the draft exists a rebuild must never create a
  # SECOND draft on the same expenses, so no post-draft step re-raises.
  #
  # Long and API-heavy, so it runs from BuildBatchJob.
  class BatchProcessor
    XLSX_CONTENT_TYPE =
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

    # How many times a post-draft write (the Batch record, a producer_notified
    # stamp) is attempted.
    WRITE_RETRY_ATTEMPTS = 3

    Result = Struct.new(:success, :bacs_date, :batch_id, :total_amount,
                        :eusa_draft_web_link, :eusa_draft_message_id, :bacs_sharepoint_url,
                        :errors, keyword_init: true)

    # xlsx: is a test seam: the BACS spreadsheet's authorisation cells are checked through it.
    def initialize(store:, graph:, cost_centre:, xlsx: BacsXlsx.new, sleeper: ->(seconds) { sleep(seconds) })
      @store = store
      @graph = graph
      @cost_centre = cost_centre
      @sleeper = sleeper
      @xlsx = xlsx
      @international_xlsx = InternationalXlsx.new
      @composer = EusaEmailComposer.new
      # Producer notifications send from the cost centre's send mailbox, so
      # they land in its Sent Items.
      @notifier = Notifier.new(cost_centre: cost_centre, graph: graph)
    end

    def process(expenses:, bacs_date:, sender_name:, eusa_recipient:,
                eusa_subject: nil, eusa_body_html: nil)
      result = new_result(expenses, bacs_date)
      return fail_with(result, "No expenses in batch.") if expenses.empty?
      unless @cost_centre.sharepoint_configured?
        return fail_with(result, "SharePoint folders not configured for #{@cost_centre.name}.")
      end

      # The approve blocker (ReviewSupport) runs on the approval path only, so
      # a claim that reached Approved another way (the settled-claim import, a
      # console fix) arrives here unchecked, and its blank payee details would
      # ask EUSA to pay nobody. Fail the WHOLE batch rather than drop rows: a
      # spreadsheet quietly short of the approved claims is harder to notice.
      bankless = expenses.reject(&:effective_has_bank_details?)
      if bankless.any?
        return fail_with(result, "#{bankless.size} #{'claim'.pluralize(bankless.size)} have " \
                                 "no bank details and cannot be paid: " \
                                 "#{bankless.map { |e| "##{e.auto_number}" }.join(', ')}. " \
                                 "Fix the payee's People record or the claim's override, " \
                                 "or move them out of Approved.")
      end

      documents = build_payment_documents(expenses, bacs_date)
      renamed = collect_receipts(expenses, bacs_date)

      upload_payment_documents(result, documents)
      urls_by_expense = upload_receipts(result, renamed)

      subject, body_html = eusa_email(expenses, bacs_date, sender_name, eusa_subject, eusa_body_html)
      attachments = documents + renamed.values.flatten

      # CARDINAL RULE: a failed draft leaves every expense Approved.
      begin
        draft = @graph.create_draft(
          mailbox: @cost_centre.send_mailbox, to: [ eusa_recipient ],
          subject: subject, html: body_html, attachments: attachments
        )
        result.eusa_draft_web_link = draft.web_link
        result.eusa_draft_message_id = draft.id
      rescue StandardError => e
        return fail_with(result, "EUSA draft creation failed: #{e.message}")
      end

      # ORPHAN-DRAFT GUARD: the draft is live. Even when the Batch write fails,
      # mark the expenses Submitted (a nil batch_id is dropped) so a rebuild
      # cannot re-draft them, still notify producers, and report the orphan.
      batch = create_batch(result)
      submitted = mark_submitted(result, expenses, batch, urls_by_expense)
      notifications_complete = notify_producers(result, submitted.reject(&:producer_notified), bacs_date)

      if batch.nil?
        result.errors.unshift(orphan_draft_message(result))
        return result
      end

      mark_producers_notified(result, batch) if notifications_complete

      # Other post-draft failures are best-effort: reported in result.errors
      # without flipping success. A mark_submitted failure is the exception:
      # that expense is in the live draft yet still Approved.
      result.success = (submitted.size == expenses.size)
      result
    rescue StandardError => e
      fail_with(result, e.message)
    end

    private

    def new_result(expenses, bacs_date)
      Result.new(success: false, bacs_date: bacs_date, batch_id: nil, total_amount: total(expenses),
                 eusa_draft_web_link: "", eusa_draft_message_id: "", bacs_sharepoint_url: "", errors: [])
    end

    def fail_with(result, message)
      result.errors << message
      result
    end

    def total(expenses)
      expenses.sum { |expense| expense.amount || 0 }
    end

    # One BACS spreadsheet for the UK claims plus one form per international
    # claim (EUSA's international form holds a single payment). The spreadsheet
    # is skipped when there are no UK claims: an empty one asks EUSA to pay nobody.
    def build_payment_documents(expenses, bacs_date)
      uk, international = expenses.partition { |expense| !expense.international? }

      documents = []
      documents << bacs_document(uk, bacs_date) if uk.any?
      documents.concat(international.map { |expense| international_document(expense, bacs_date) })
      documents
    end

    def bacs_document(expenses, bacs_date)
      rows = expenses.map do |expense|
        BacsXlsx::BacsRow.new(
          payee_name: expense.effective_payee_name, amount: expense.amount,
          sort_code: expense.effective_sort_code, account_number: expense.effective_account_number,
          nominal_code: expense.effective_nominal_code, description: expense.description,
          payment_reference: expense.payment_reference, cost_centre: @cost_centre.eusa_code
        )
      end
      filename = "#{bacs_date.iso8601}-#{@cost_centre.slug}-BACS-request-#{@cost_centre.eusa_code}.xlsx"
      xlsx_attachment(filename, @xlsx.generate(rows, centre_name: @cost_centre.name,
                                                     authoriser_name: @cost_centre.authoriser_name,
                                                     authoriser_designation: @cost_centre.authoriser_designation))
    end

    # The amount on the form is the FOREIGN one: EUSA's bank pays the supplier
    # in their own currency; the GBP figure is only what our budgets count.
    def international_document(expense, bacs_date)
      payment = InternationalXlsx::Payment.new(
        payee_name: expense.effective_payee_name,
        amount: expense.foreign_amount, currency: expense.foreign_currency,
        description: expense.description, date_required: bacs_date,
        nominal_code: expense.effective_nominal_code, cost_centre: @cost_centre.eusa_code,
        bic: expense.effective_bic, iban: expense.effective_iban
      )
      filename = FilenameSanitizer.build_international_form_filename(
        bacs_date: bacs_date, cost_centre_slug: @cost_centre.slug,
        payee_name: expense.effective_payee_name, auto_number: expense.auto_number
      )
      xlsx_attachment(filename, @international_xlsx.generate(payment))
    end

    # Expense record id => renamed receipt attachments.
    def collect_receipts(expenses, bacs_date)
      expenses.each_with_object({}) do |expense, acc|
        acc[expense.record_id] = expense.receipts.each_with_index.map do |receipt, index|
          filename = FilenameSanitizer.build_receipt_filename(
            bacs_date: bacs_date, budget_name: expense.budget&.display_name.to_s,
            description: expense.description.to_s, original_filename: receipt.filename, index: index + 1
          )
          GraphClient::Attachment.new(
            filename: filename, content: receipt.bytes,
            content_type: receipt.content_type.presence || "application/octet-stream"
          )
        end
      end
    end

    # Best-effort and per document: a SharePoint outage must not block sending
    # to EUSA. bacs_sharepoint_url keeps the first upload (the BACS sheet when
    # there is one), the link the batch record quotes.
    def upload_payment_documents(result, documents)
      folder = @cost_centre.bacs_folder
      documents.each do |document|
        url = @graph.upload_to_folder(drive_id: folder.drive_id, folder_id: folder.folder_id,
                                      filename: document.filename, content: document.content)
        result.bacs_sharepoint_url = url if result.bacs_sharepoint_url.blank?
      rescue StandardError => e
        result.errors << "SharePoint upload failed for #{document.filename}: #{e.message}"
      end
    end

    def upload_receipts(result, renamed)
      folder = @cost_centre.receipts_folder
      renamed.transform_values do |attachments|
        attachments.filter_map do |attachment|
          @graph.upload_to_folder(drive_id: folder.drive_id, folder_id: folder.folder_id,
                                  filename: attachment.filename, content: attachment.content)
        rescue StandardError => e
          result.errors << "Receipt upload failed for #{attachment.filename}: #{e.message}"
          nil
        end
      end
    end

    def eusa_email(expenses, bacs_date, sender_name, subject_override, body_override)
      return [ subject_override, body_override ] if subject_override.present? && body_override.present?

      email = @composer.compose(expenses: expenses, bacs_date: bacs_date, sender_name: sender_name,
                                cost_centre: @cost_centre)
      [ subject_override.presence || email.subject, body_override.presence || email.body_html ]
    end

    def xlsx_attachment(filename, bytes)
      GraphClient::Attachment.new(filename: filename, content: bytes, content_type: XLSX_CONTENT_TYPE)
    end

    # Retried, since the draft is already live. A retry first reuses a batch
    # the previous attempt wrote despite raising (a lost response, not a lost
    # request). Returns nil when every attempt failed: the orphan-draft path.
    def create_batch(result)
      batch = with_write_retry do |attempt|
        (attempt > 1 && @store.find_batch_by_draft_message_id(result.eusa_draft_message_id)) ||
          # draft_web_link is stored because Graph returns it only once, here;
          # it cannot be derived from the message id later.
          @store.create_batch!(date_sent: result.bacs_date,
                               notes: "BACS SharePoint: #{result.bacs_sharepoint_url}",
                               sharepoint_backup_url: result.bacs_sharepoint_url,
                               draft_message_id: result.eusa_draft_message_id,
                               draft_web_link: result.eusa_draft_web_link.presence)
      end
      result.batch_id = batch.record_id
      batch
    rescue StandardError => e
      fail_with(result, "Failed to create batch record after #{WRITE_RETRY_ATTEMPTS} attempts: #{e.message}")
      nil
    end

    # Returns the expenses actually marked Submitted, so only their producers
    # are notified. +batch+ is nil on the orphan-draft path.
    def mark_submitted(result, expenses, batch, urls_by_expense)
      batch_id = batch&.record_id
      expenses.select do |expense|
        urls = urls_by_expense.fetch(expense.record_id, [])
        # Re-read before writing: the Approved set was picked minutes ago, and
        # limits_concurrency serialises builds of the SAME centre only (or a
        # human re-typed the claim mid-run).
        current = @store.find_expense(expense.record_id)
        unless current&.status == Status::APPROVED
          result.errors << "ALREADY CLAIMED: expense #{expense.auto_number} is no longer Approved " \
            "(now #{current&.status || 'deleted'}), so something else has taken it since this batch " \
            "was selected. It IS in this run's EUSA draft (#{result.eusa_draft_web_link}). Check it " \
            "is not about to be paid twice before you send that draft."
          next false
        end
        with_write_retry do
          @store.update_expense!(expense.record_id, status: Status::SUBMITTED, batch_id: batch_id,
                                 submitted_to_eusa_date: result.bacs_date,
                                 receipts_offloaded: receipts_offloaded?(expense, urls),
                                 sharepoint_receipt_urls: urls)
        end
        true
      rescue StandardError => e
        result.errors << "SUBMIT FAILED (DOUBLE-DRAFT RISK): could not mark expense " \
          "#{expense.auto_number} as Submitted after #{WRITE_RETRY_ATTEMPTS} attempts, even though " \
          "it is included in the live EUSA draft (#{result.eusa_draft_web_link}). Fix this " \
          "expense's status manually before rebuilding, or it will be drafted a second time: #{e.message}"
        false
      end
    end

    # True only when every receipt uploaded: otherwise an operator could delete
    # the only copy of a receipt that was never backed up.
    def receipts_offloaded?(expense, uploaded_urls)
      expense.receipts.size == uploaded_urls.size
    end

    def orphan_draft_message(result)
      "ORPHAN DRAFT: the EUSA draft was created (#{result.eusa_draft_web_link}) but the batch record " \
        "could not be saved. The expenses were marked Submitted to stop a rebuild creating a SECOND " \
        "draft. Send THIS existing draft and repair the batch record manually. DO NOT rebuild."
    end

    # One email per payee, to the LINKED person (an override only steers the
    # money). Only payees whose send succeeded are stamped, so a rebuild
    # re-notifies the rest. Returns whether notification is COMPLETE (nothing
    # left to send, or every send succeeded), so the batch flag is accurate.
    def notify_producers(result, to_notify, bacs_date)
      grouped = to_notify.group_by { |expense| expense.person&.email.to_s.strip }
                         .reject { |email, _| email.blank? }
      return true if grouped.empty?

      sent_emails = grouped.filter_map do |email, items|
        email if deliver_producer_email(result, email, items, bacs_date)
      end
      mark_notified(result, to_notify, sent_emails)
      sent_emails.size == grouped.size
    end

    # False when the send failed; the failure is collected, never raised.
    def deliver_producer_email(result, email, items, bacs_date)
      line_items = items.map do |expense|
        { auto_number: expense.auto_number, record_id: expense.record_id,
          amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.display_name.to_s,
          description: expense.description.to_s }
      end
      @notifier.producer_notification(
        to: email, greeting_name: GreetingName.for(items.first.person),
        line_items: line_items, bacs_date: bacs_date, total: format("%.2f", total(items))
      )
      true
    rescue StandardError => e
      result.errors << "Producer notification failed for #{email}: #{e.message}"
      false
    end

    def mark_notified(result, to_notify, notified_emails)
      to_notify.each do |expense|
        next unless notified_emails.include?(expense.person&.email.to_s.strip)

        with_write_retry { @store.update_expense!(expense.record_id, producer_notified: true) }
      rescue StandardError => e
        result.errors << "Failed to mark producer_notified on #{expense.auto_number} after " \
          "#{WRITE_RETRY_ATTEMPTS} attempts; their notification email was already sent, so a " \
          "rebuild risks emailing them twice: #{e.message}"
      end
    end

    def mark_producers_notified(result, batch)
      @store.update_batch!(batch.record_id, producer_notifications_sent: true)
    rescue StandardError => e
      result.errors << "Failed to flag batch producer_notifications_sent: #{e.message}"
    end

    # Retries with a 1s/2s back-off, yielding the 1-based attempt number
    # (create_batch dedups on a retry). Re-raises when attempts run out.
    def with_write_retry
      attempts = 0
      begin
        attempts += 1
        yield attempts
      rescue StandardError
        raise unless attempts < WRITE_RETRY_ATTEMPTS

        @sleeper.call(attempts)
        retry
      end
    end
  end
end
