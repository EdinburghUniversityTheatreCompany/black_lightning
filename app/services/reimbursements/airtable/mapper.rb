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
          budget_type: fields[fid(:budgets, :budget_type)] || "Expense"
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
          payment_reference: fields[fid(:expenses, :payment_reference)].to_s,
          rejection_reason: fields[fid(:expenses, :rejection_reason)].to_s,
          submitted_at: time(fields[fid(:expenses, :submitted_at)]),
          ai_check_status: fields[fid(:expenses, :ai_check_status)].to_s,
          ai_comment: fields[fid(:expenses, :ai_comment)].to_s
        )
      end

      # Attribute hash (symbol keys) -> field-ID payload. Nil values are
      # omitted so email-in submissions can be created with gaps.
      def expense_fields(attrs)
        attrs.compact.each_with_object({}) do |(key, value), payload|
          case key
          when :person_record_id then payload[fid(:expenses, :payee)] = [ value ]
          when :budget_record_id then payload[fid(:expenses, :budget)] = [ value ]
          when :amount, :amount_excl_vat then payload[fid(:expenses, key)] = value.to_f
          when :expense_type then payload[fid(:expenses, :type)] = value
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

      def attachments(raw)
        Array(raw).map do |attachment|
          Attachment.new(
            attachment_id: attachment["id"],
            filename: attachment["filename"].to_s,
            url: attachment["url"].to_s,
            size_bytes: attachment["size"].to_i,
            content_type: attachment["type"].to_s
          )
        end
      end
    end
  end
end
