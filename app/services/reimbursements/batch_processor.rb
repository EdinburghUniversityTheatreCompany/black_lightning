module Reimbursements
  ##
  # Orchestrates one BACS submission, ported from bedlam-bacs batch_processor.py.
  # A single #process call, triggered from Build Batch, does everything:
  #
  #   1. generate the BACS xlsx from the EFFECTIVE payee/sort/account/nominal
  #   2. download every receipt (Airtable URLs expire) and rename them
  #   3. upload the xlsx + receipts to the cost centre's SharePoint folders
  #   4. create the EUSA draft in the cost centre's send mailbox
  #   5. create the Batch record, mark expenses Submitted + link + store URLs
  #   6. email producer notifications (skip anyone already notified)
  #
  # THE CARDINAL RULE: expenses are never marked Submitted unless the EUSA draft
  # was created — a failed draft returns early with the expenses still Approved,
  # so a rebuild is clean. Steps after the draft are best-effort — SharePoint
  # uploads, producer emails, Batch-record flags — and their failures are
  # collected into Result#errors without undoing a valid submission.
  #
  # The one exception is mark_submitted itself: an expense whose Submitted
  # write fails is left in the SAME double-draft danger the orphan-draft guard
  # below exists to prevent (already in the live draft, but not yet flipped out
  # of the Approved queue), so #success reflects whether EVERY expense actually
  # made it to Submitted, not merely whether the draft was created.
  #
  # ORPHAN-DRAFT GUARD: once the draft exists a rebuild must never create a
  # SECOND draft on the same expenses. So every post-draft step is contained
  # here (never re-raised past the draft), the Batch-record write is retried,
  # and if it still can't be written the expenses are marked Submitted anyway —
  # leaving the Approved queue so a rebuild finds nothing to re-draft — while a
  # loud error naming the live draft link is surfaced for manual repair.
  #
  # It's long and API-heavy, so it's built to run from a Solid Queue job
  # (BuildBatchJob for interactive Build Batch, NightlyBatchJob for the nightly).
  class BatchProcessor
    XLSX_CONTENT_TYPE =
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

    # How many times to retry a post-draft Airtable write (the Batch record, or
    # a producer_notified stamp) before giving up. Retries are immediate: a
    # transient Airtable blip clears, and we must not sit on a live draft.
    WRITE_RETRY_ATTEMPTS = 3

    # The outcome handed back to the UI.
    Result = Struct.new(:success, :bacs_date, :batch_id, :expense_count, :total_amount,
                        :eusa_draft_web_link, :eusa_draft_message_id, :bacs_sharepoint_url,
                        :producer_notifications_sent, :receipts_uploaded, :errors, keyword_init: true)

    def initialize(store:, graph:, cost_centre:, xlsx: nil, composer: nil, notifier: nil)
      @store = store
      @graph = graph
      @cost_centre = cost_centre
      @xlsx = xlsx || BacsXlsx.new
      @composer = composer || EusaEmailComposer.new
      # Producer notifications send through Graph from the cost centre's send
      # mailbox (same client as the EUSA draft), so they land in its Sent Items.
      @notifier = notifier || Notifier.new(mailbox: cost_centre.send_mailbox, graph: graph)
    end

    def process(expenses:, bacs_date:, sender_name:, eusa_recipient:,
                eusa_subject: nil, eusa_body_html: nil, eusa_contact_name: "")
      result = new_result(expenses, bacs_date)
      return fail_with(result, "No expenses in batch.") if expenses.empty?
      unless @cost_centre.sharepoint_configured?
        return fail_with(result, "SharePoint folders not configured for #{@cost_centre.name}.")
      end

      xlsx_bytes = build_xlsx(expenses)
      renamed = collect_receipts(expenses, bacs_date)

      bacs_filename = "#{bacs_date.iso8601}-bedlam-fringe-BACS-request-#{@cost_centre.eusa_code}.xlsx"
      upload_bacs_file(result, bacs_filename, xlsx_bytes)
      urls_by_expense = upload_receipts(result, renamed)

      subject, body_html = eusa_email(expenses, bacs_date, sender_name, eusa_subject,
                                      eusa_body_html, eusa_contact_name)
      attachments = [ xlsx_attachment(bacs_filename, xlsx_bytes) ] + renamed.values.flatten

      # CARDINAL RULE — a failed draft leaves every expense Approved.
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

      # ORPHAN-DRAFT GUARD — the draft is live and money will move once the
      # operator sends it. If the Batch write can't be recovered, still mark the
      # expenses Submitted so they leave the Approved queue (a rebuild can't
      # re-draft them) and surface the orphan draft loudly for manual repair.
      batch = create_batch(result)
      if batch.nil?
        submitted = mark_submitted(result, expenses, nil, urls_by_expense)
        notify_producers(result, submitted.reject(&:producer_notified), bacs_date)
        result.errors.unshift(orphan_draft_message(result))
        return result
      end

      submitted = mark_submitted(result, expenses, batch, urls_by_expense)
      notify_producers(result, submitted.reject(&:producer_notified), bacs_date)
      flag_batch(result, batch, :producer_notifications_sent) if result.producer_notifications_sent.positive?

      # Every OTHER post-draft step (SharePoint uploads, producer emails, the
      # Batch-record flags) is genuinely best-effort: their failure is real but
      # doesn't put the batch in an inconsistent, double-draft-risking state, so
      # it's collected into result.errors without flipping success. A
      # mark_submitted failure is different — that expense is still Approved
      # despite being in the live draft, the same double-draft risk the
      # orphan-draft guard exists to prevent — so success reflects whether
      # EVERY expense actually made it to Submitted.
      result.success = (submitted.size == expenses.size)
      result
    rescue StandardError => e
      fail_with(result, e.message)
    end

    private

    def new_result(expenses, bacs_date)
      Result.new(success: false, bacs_date: bacs_date, batch_id: nil,
                 expense_count: expenses.size, total_amount: total(expenses),
                 eusa_draft_web_link: "", eusa_draft_message_id: "", bacs_sharepoint_url: "",
                 producer_notifications_sent: 0, receipts_uploaded: 0, errors: [])
    end

    def fail_with(result, message)
      result.errors << message
      result
    end

    def total(expenses)
      expenses.sum { |expense| expense.amount || 0 }
    end

    def build_xlsx(expenses)
      rows = expenses.map do |expense|
        BacsXlsx::BacsRow.new(
          payee_name: expense.effective_payee_name, amount: expense.amount,
          sort_code: expense.effective_sort_code, account_number: expense.effective_account_number,
          nominal_code: expense.effective_nominal_code, description: expense.description,
          payment_reference: expense.payment_reference, cost_centre: @cost_centre.eusa_code
        )
      end
      @xlsx.generate(rows)
    end

    # Expense record id -> renamed GraphClient::Attachments, ready to upload/attach.
    def collect_receipts(expenses, bacs_date)
      expenses.each_with_object({}) do |expense, acc|
        acc[expense.record_id] = expense.receipts.each_with_index.map do |receipt, index|
          filename = FilenameSanitizer.build_receipt_filename(
            bacs_date: bacs_date, budget_name: expense.budget&.name.to_s,
            description: expense.description.to_s, original_filename: receipt.filename, index: index + 1
          )
          GraphClient::Attachment.new(
            filename: filename, content: @graph.download(receipt.url),
            content_type: receipt.content_type.presence || "application/octet-stream"
          )
        end
      end
    end

    # Best-effort: a SharePoint outage shouldn't block sending to EUSA.
    def upload_bacs_file(result, filename, bytes)
      folder = @cost_centre.bacs_folder
      result.bacs_sharepoint_url = @graph.upload_to_folder(
        drive_id: folder.drive_id, folder_id: folder.folder_id, filename: filename, content: bytes
      )
    rescue StandardError => e
      result.errors << "BACS file SharePoint upload failed: #{e.message}"
    end

    def upload_receipts(result, renamed)
      folder = @cost_centre.receipts_folder
      renamed.transform_values do |attachments|
        attachments.filter_map do |attachment|
          url = @graph.upload_to_folder(drive_id: folder.drive_id, folder_id: folder.folder_id,
                                        filename: attachment.filename, content: attachment.content)
          result.receipts_uploaded += 1
          url
        rescue StandardError => e
          result.errors << "Receipt upload failed for #{attachment.filename}: #{e.message}"
          nil
        end
      end
    end

    def eusa_email(expenses, bacs_date, sender_name, subject_override, body_override, contact)
      return [ subject_override, body_override ] if subject_override.present? && body_override.present?

      email = @composer.compose(expenses: expenses, bacs_date: bacs_date, sender_name: sender_name,
                                eusa_code: @cost_centre.eusa_code, eusa_contact_name: contact)
      [ subject_override.presence || email.subject, body_override.presence || email.body_html ]
    end

    def xlsx_attachment(filename, bytes)
      GraphClient::Attachment.new(filename: filename, content: bytes, content_type: XLSX_CONTENT_TYPE)
    end

    # Writes the Batch record, retrying transient failures — the draft is
    # already live, so we must recover rather than sit on it. Returns nil only
    # when every attempt failed (the caller then invokes the orphan-draft guard).
    def create_batch(result)
      attempts = 0
      begin
        attempts += 1
        batch = @store.create_batch!(date_sent: result.bacs_date,
                                     notes: "BACS SharePoint: #{result.bacs_sharepoint_url}")
        result.batch_id = batch.record_id
        # Store the EUSA draft's message id so a reopen can delete the stale draft.
        flag_batch(result, batch, :eusa_draft_created,
                   sharepoint_backup_url: result.bacs_sharepoint_url,
                   draft_message_id: result.eusa_draft_message_id)
        batch
      rescue StandardError => e
        retry if attempts < WRITE_RETRY_ATTEMPTS
        fail_with(result, "Failed to create batch record after #{attempts} attempts: #{e.message}")
        nil
      end
    end

    # +batch+ is nil on the orphan-draft path; batch_id: nil is dropped by the
    # mapper so the batch link is simply left unset (the expense still leaves the
    # Approved queue, which is what stops a rebuild re-drafting it).
    #
    # Returns the subset of +expenses+ actually confirmed Submitted, so callers
    # (producer notification) only act on expenses that genuinely made it —
    # never on one whose write below failed.
    def mark_submitted(result, expenses, batch, urls_by_expense)
      batch_id = batch&.record_id
      expenses.select do |expense|
        urls = urls_by_expense.fetch(expense.record_id, [])
        @store.update_expense!(expense.record_id, status: Status::SUBMITTED, batch_id: batch_id,
                               submitted_to_eusa_date: result.bacs_date,
                               receipts_offloaded: receipts_offloaded?(expense, urls),
                               sharepoint_receipt_urls: urls)
        true
      rescue StandardError => e
        result.errors << "SUBMIT FAILED — DOUBLE-DRAFT RISK: could not mark expense " \
          "#{expense.auto_number} as Submitted even though it is included in the live EUSA " \
          "draft (#{result.eusa_draft_web_link}). Fix this expense's status manually before " \
          "rebuilding, or it will be drafted a second time: #{e.message}"
        false
      end
    end

    # Only true when every receipt this expense actually had was successfully
    # uploaded to SharePoint — an expense with no receipts has nothing to
    # offload (trivially true), but a partial or total upload failure must not
    # be reported as offloaded, or an operator could delete the only copy of a
    # receipt that was never actually backed up.
    def receipts_offloaded?(expense, uploaded_urls)
      expense.receipts.size == uploaded_urls.size
    end

    def orphan_draft_message(result)
      "ORPHAN DRAFT: the EUSA draft was created (#{result.eusa_draft_web_link}) but the batch record " \
        "could not be saved. The expenses were marked Submitted to stop a rebuild creating a SECOND " \
        "draft — send THIS existing draft and repair the batch record manually. DO NOT rebuild."
    end

    # Producer notifications go via Graph (Notifier#producer_notification), one
    # per payee, keyed off the LINKED person's email (not the effective override
    # — that only steers the money). Anyone already notified for this batch is
    # skipped. A send failure is collected into result.errors, never raised —
    # and only the payees whose send actually succeeded are stamped
    # producer_notified, so a rebuild re-notifies anyone the send missed.
    def notify_producers(result, to_notify, bacs_date)
      grouped = to_notify.group_by { |expense| expense.person&.email.to_s.strip }
                         .reject { |email, _| email.blank? }

      sent_emails = grouped.filter_map do |email, items|
        email if deliver_producer_email(result, email, items, bacs_date)
      end
      mark_notified(result, to_notify, sent_emails)
    end

    # Returns true when the send succeeded (so the caller can stamp the payee),
    # false when it failed (collected into result.errors, never raised).
    def deliver_producer_email(result, email, items, bacs_date)
      line_items = items.map do |expense|
        { amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.name.to_s,
          description: expense.description.to_s }
      end
      @notifier.producer_notification(
        to: email, recipient_name: items.first.person&.name.to_s,
        line_items: line_items, bacs_date: bacs_date, total: format("%.2f", total(items))
      )
      result.producer_notifications_sent += 1
      true
    rescue StandardError => e
      result.errors << "Producer notification failed for #{email}: #{e.message}"
      false
    end

    def mark_notified(result, to_notify, notified_emails)
      to_notify.each do |expense|
        next unless notified_emails.include?(expense.person&.email.to_s.strip)

        attempts = 0
        begin
          attempts += 1
          @store.update_expense!(expense.record_id, producer_notified: true)
        rescue StandardError => e
          retry if attempts < WRITE_RETRY_ATTEMPTS
          result.errors << "Failed to mark producer_notified on #{expense.auto_number} after " \
            "#{attempts} attempts — their notification email was already sent, so a rebuild " \
            "risks emailing them twice: #{e.message}"
        end
      end
    end

    def flag_batch(result, batch, flag, extra = {})
      @store.update_batch!(batch.record_id, { flag => true }.merge(extra))
    rescue StandardError => e
      result.errors << "Failed to flag batch #{flag}: #{e.message}"
    end
  end
end
