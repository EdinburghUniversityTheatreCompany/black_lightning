module Reimbursements
  module Airtable
    ##
    # Translates between Airtable's field-ID-keyed record hashes and the
    # Reimbursements POROs, in both directions.
    class Mapper
      def initialize(config)
        @config = config
      end

      def person(record)
        fields = record.fetch("fields", {})
        Person.new(
          record_id: record.fetch("id"),
          name: fields[fid(:people, :name)].to_s,
          email: fields[fid(:people, :email)].to_s,
          sort_code: fields[fid(:people, :sort_code)].to_s,
          account_number: fields[fid(:people, :account_number)].to_s,
          verified: fields[fid(:people, :verified)].present?,
          notes: fields[fid(:people, :notes)].to_s
        )
      end

      def budget(record)
        fields = record.fetch("fields", {})
        Budget.new(
          record_id: record.fetch("id"),
          name: fields[fid(:budgets, :name)].to_s,
          nominal_code: fields[fid(:budgets, :nominal_code)].to_s,
          active: fields[fid(:budgets, :active)].present?,
          budget_type: fields[fid(:budgets, :budget_type)] || "Expense",
          initial_budget: decimal(fields[fid(:budgets, :initial_budget)]),
          remaining: decimal(fields[fid(:budgets, :remaining)])
        )
      end

      def expense(record, people_by_id:, budgets_by_id:)
        fields = record.fetch("fields", {})
        Expense.new(
          record_id: record.fetch("id"),
          auto_number: fields[fid(:expenses, :auto_number)],
          person: people_by_id[Array(fields[fid(:expenses, :payee)]).first],
          amount: decimal(fields[fid(:expenses, :amount)]),
          amount_excl_vat: decimal(fields[fid(:expenses, :amount_excl_vat)]),
          budget: budgets_by_id[Array(fields[fid(:expenses, :budget)]).first],
          description: fields[fid(:expenses, :description)].to_s,
          receipts: attachments(fields[fid(:expenses, :receipt)]),
          status: fields[fid(:expenses, :status)].to_s,
          expense_type: fields[fid(:expenses, :type)] || Expense::TYPE_REIMBURSEMENT,
          payee_name_override: fields[fid(:expenses, :payee_name_override)].to_s,
          sort_code_override: fields[fid(:expenses, :sort_code_override)].to_s,
          account_number_override: fields[fid(:expenses, :account_number_override)].to_s,
          nominal_code_override: fields[fid(:expenses, :nominal_code_override)].to_s,
          payment_reference: fields[fid(:expenses, :payment_reference)].to_s,
          rejection_reason: fields[fid(:expenses, :rejection_reason)].to_s,
          submitted_at: time(fields[fid(:expenses, :submitted_at)]),
          submitted_to_eusa_date: date(fields[fid(:expenses, :submitted_to_eusa_date)]),
          payment_confirmed_date: date(fields[fid(:expenses, :payment_confirmed_date)]),
          batch_id: Array(fields[fid(:expenses, :batch)]).first,
          producer_notified: fields[fid(:expenses, :producer_notified)].present?,
          receipts_offloaded: fields[fid(:expenses, :receipts_offloaded)].present?,
          sharepoint_receipt_urls: multiline(fields[fid(:expenses, :sharepoint_receipt_urls)]),
          ai_check_status: fields[fid(:expenses, :ai_check_status)].to_s,
          ai_comment: fields[fid(:expenses, :ai_comment)].to_s,
          ai_checked_at: time(fields[fid(:expenses, :ai_checked_at)])
        )
      end

      def batch(record)
        fields = record.fetch("fields", {})
        Batch.new(
          record_id: record.fetch("id"),
          name: fields[fid(:batches, :name)].to_s,
          date_sent: date(fields[fid(:batches, :date_sent)]),
          sharepoint_backup_url: fields[fid(:batches, :sharepoint_backup_url)].to_s,
          eusa_draft_created: fields[fid(:batches, :eusa_draft_created)].present?,
          producer_notifications_sent: fields[fid(:batches, :producer_notifications_sent)].present?,
          notes: fields[fid(:batches, :notes)].to_s
        )
      end

      def eusa_actual(record)
        fields = record.fetch("fields", {})
        EusaActual.new(
          record_id: record.fetch("id"),
          nominal_code: fields[fid(:eusa_actuals, :nominal_code)].to_s,
          cost_centre: fields[fid(:eusa_actuals, :cost_centre)].to_s,
          ref: fields[fid(:eusa_actuals, :ref)].to_s,
          date: date(fields[fid(:eusa_actuals, :date)]),
          period: fields[fid(:eusa_actuals, :period)].to_s,
          narrative: fields[fid(:eusa_actuals, :narrative)].to_s,
          narrative_1: fields[fid(:eusa_actuals, :narrative_1)].to_s,
          debit: decimal(fields[fid(:eusa_actuals, :debit)]),
          credit: decimal(fields[fid(:eusa_actuals, :credit)]),
          net: decimal(fields[fid(:eusa_actuals, :net)]),
          linked_expense_ids: Array(fields[fid(:eusa_actuals, :linked_expense)]),
          linked_budget_ids: Array(fields[fid(:eusa_actuals, :linked_budget)]),
          source_month: fields[fid(:eusa_actuals, :source_month)].to_s,
          imported_at: time(fields[fid(:eusa_actuals, :imported_at)])
        )
      end

      # Attribute hash (symbol keys) -> field-ID payload. Nil values are
      # omitted so email-in submissions can be created with gaps. Operator write
      # fields (status transitions, batch link, EUSA dates, SharePoint URLs, AI
      # verdict) go through the same writer.
      def expense_fields(attrs)
        attrs.compact.each_with_object({}) do |(key, value), payload|
          case key
          when :person_record_id then payload[fid(:expenses, :payee)] = [ value ]
          when :budget_record_id then payload[fid(:expenses, :budget)] = [ value ]
          when :batch_id then payload[fid(:expenses, :batch)] = [ value ]
          when :amount, :amount_excl_vat then payload[fid(:expenses, key)] = value.to_f
          when :expense_type then payload[fid(:expenses, :type)] = value
          when :submitted_to_eusa_date, :payment_confirmed_date
            payload[fid(:expenses, key)] = date_string(value)
          when :ai_checked_at, :rejection_notified
            payload[fid(:expenses, key)] = time_string(value)
          when :sharepoint_receipt_urls
            payload[fid(:expenses, key)] = Array(value).join("\n")
          else payload[fid(:expenses, key)] = value
          end
        end
      end

      def person_fields(attrs)
        attrs.compact.transform_keys { |key| fid(:people, key) }
      end

      private

      def fid(table, field)
        @config.fid(table, field)
      end

      def decimal(value)
        return nil if value.nil?

        BigDecimal(value.to_s)
      end

      def time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      end

      # Airtable date fields arrive as "YYYY-MM-DD" (or an ISO datetime); keep
      # just the date. Returns nil for a blank/unparseable value.
      def date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue Date::Error
        nil
      end

      def date_string(value)
        value.is_a?(Date) || value.is_a?(Time) ? value.strftime("%Y-%m-%d") : value
      end

      def time_string(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value
      end

      # SharePoint receipt URLs are stored one-per-line in a multiline field.
      def multiline(value)
        value.to_s.split("\n").map(&:strip).reject(&:blank?)
      end

      def attachments(raw)
        Array(raw).map do |attachment|
          Attachment.new(
            attachment_id: attachment["id"],
            filename: attachment["filename"].to_s,
            url: attachment["url"].to_s,
            size_bytes: attachment["size"].to_i,
            content_type: attachment["type"].to_s,
            thumbnail_url: attachment.dig("thumbnails", "large", "url") ||
                           attachment.dig("thumbnails", "small", "url")
          )
        end
      end
    end
  end
end
