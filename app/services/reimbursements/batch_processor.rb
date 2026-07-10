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
  # so a rebuild is clean. Steps after the draft are best-effort: their failures
  # are collected into Result#errors but don't undo a valid submission.
  #
  # It's long and API-heavy, so it's built to run from a Solid Queue job; today
  # Build Batch runs it inline for immediate operator feedback (the draft link).
  class BatchProcessor
    XLSX_CONTENT_TYPE =
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

    # The outcome handed back to the UI.
    Result = Struct.new(:success, :bacs_date, :batch_id, :expense_count, :total_amount,
                        :eusa_draft_web_link, :bacs_sharepoint_url, :producer_notifications_sent,
                        :receipts_uploaded, :errors, keyword_init: true)

    def initialize(store:, graph:, cost_centre:, xlsx: nil, composer: nil, mailer: nil)
      @store = store
      @graph = graph
      @cost_centre = cost_centre
      @xlsx = xlsx || BacsXlsx.new
      @composer = composer || EusaEmailComposer.new
      @mailer = mailer || BatchMailer
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
        result.eusa_draft_web_link = @graph.create_draft(
          mailbox: @cost_centre.send_mailbox, to: [ eusa_recipient ],
          subject: subject, html: body_html, attachments: attachments
        )
      rescue StandardError => e
        return fail_with(result, "EUSA draft creation failed: #{e.message}")
      end

      batch = create_batch(result)
      return result if batch.nil?

      mark_submitted(result, expenses, batch, urls_by_expense)
      notify_producers(result, expenses.reject(&:producer_notified), bacs_date)
      flag_batch(result, batch, :producer_notifications_sent)

      result.success = true
      result
    rescue StandardError => e
      fail_with(result, e.message)
    end

    private

    def new_result(expenses, bacs_date)
      Result.new(success: false, bacs_date: bacs_date, batch_id: nil,
                 expense_count: expenses.size, total_amount: total(expenses),
                 eusa_draft_web_link: "", bacs_sharepoint_url: "",
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

    def create_batch(result)
      batch = @store.create_batch!(date_sent: result.bacs_date,
                                   notes: "BACS SharePoint: #{result.bacs_sharepoint_url}")
      result.batch_id = batch.record_id
      flag_batch(result, batch, :eusa_draft_created, sharepoint_backup_url: result.bacs_sharepoint_url)
      batch
    rescue StandardError => e
      fail_with(result, "Failed to create batch record: #{e.message}")
      nil
    end

    def mark_submitted(result, expenses, batch, urls_by_expense)
      expenses.each do |expense|
        @store.update_expense!(expense.record_id, status: Status::SUBMITTED, batch_id: batch.record_id,
                               submitted_to_eusa_date: result.bacs_date, receipts_offloaded: true,
                               sharepoint_receipt_urls: urls_by_expense.fetch(expense.record_id, []))
      rescue StandardError => e
        result.errors << "Failed to mark expense #{expense.auto_number} as Submitted: #{e.message}"
      end
    end

    # Producer notifications go via ActionMailer (deliver_later), one per payee,
    # keyed off the LINKED person's email (not the effective override — that only
    # steers the money). Anyone already notified for this batch is skipped.
    def notify_producers(result, to_notify, bacs_date)
      grouped = to_notify.group_by { |expense| expense.person&.email.to_s.strip }
                         .reject { |email, _| email.blank? }

      grouped.each do |email, items|
        deliver_producer_email(result, email, items, bacs_date)
      end
      mark_notified(result, to_notify, grouped.keys)
    end

    def deliver_producer_email(result, email, items, bacs_date)
      line_items = items.map do |expense|
        { amount: format("%.2f", expense.amount || 0), budget_name: expense.budget&.name.to_s,
          description: expense.description.to_s }
      end
      @mailer.producer_notification(
        recipient_email: email, recipient_name: items.first.person&.name.to_s,
        line_items: line_items, bacs_date: bacs_date, total: format("%.2f", total(items))
      ).deliver_later
      result.producer_notifications_sent += 1
    rescue StandardError => e
      result.errors << "Producer notification failed for #{email}: #{e.message}"
    end

    def mark_notified(result, to_notify, notified_emails)
      to_notify.each do |expense|
        next unless notified_emails.include?(expense.person&.email.to_s.strip)

        begin
          @store.update_expense!(expense.record_id, producer_notified: true)
        rescue StandardError => e
          result.errors << "Failed to mark producer_notified on #{expense.auto_number}: #{e.message}"
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
