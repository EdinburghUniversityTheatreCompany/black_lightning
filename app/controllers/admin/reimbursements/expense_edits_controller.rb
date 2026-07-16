require "csv"

module Admin
  module Reimbursements
    ##
    # Finance-only editing of a single expense at ANY status — Pending,
    # Approved, Submitted AND Paid. The Business Manager wants full
    # flexibility, so there is deliberately NO +editable?+/status guard here
    # (that guard belongs to the producer portal path, where a submitter may
    # only touch their own Draft/Pending expense).
    #
    # Reachable from the Review cards' "Edit (any status)" link and from a
    # lookup by auto-number or Airtable record id (so a Submitted/Paid expense
    # that never appears on the Review tabs can still be found). Edits persist
    # through +store.update_expense!+, which is status-agnostic; a Submitted or
    # Paid expense shows a clear note that the edit won't change what EUSA has
    # already processed.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class ExpenseEditsController < FinanceController
      # Injection seam for tests: the modulus checker (from the vendored Pay.UK
      # rule files in production; a fake in functional tests).
      class_attribute :checker_builder, default: -> { ::Reimbursements::ModulusCheck.default_checker }

      helper_method :modulus_checker

      # All expenses as a filterable/searchable table, newest first, each row
      # opening the edit page above. The finance team's primary way in — the
      # old +find+ lookup is now just the search box on this page.
      def index
        @title = "Expenses"
        @statuses = ::Reimbursements::Status.all
        @budgets = store.budgets.sort_by { |b| b.name.to_s }
        @budget_by_id = store.budgets.index_by(&:record_id)

        @status_filter = params[:status].to_s.strip
        @budget_filter = params[:budget].to_s.strip
        @query = params[:q].to_s.strip
        @attention_only = params[:attention] == "1"

        filtered = filtered_expenses
        respond_to do |format|
          # Paginate the filtered set in Ruby (Airtable free plan — the whole
          # list is cached and filtered in-process, so we page the array).
          format.html { @expenses = Kaminari.paginate_array(filtered).page(params[:page]).per(50) }
          # Export the FULL filtered set (the on-screen filters carry through the
          # query string) — pagination is display-only, so the CSV isn't paged.
          format.csv do
            send_data expenses_csv(filtered), type: "text/csv",
                                              filename: "reimbursements-expenses-#{Date.current.iso8601}.csv"
          end
        end
      end

      # Lookup: resolve a typed auto-number or record id to its edit page.
      def find
        @title = "Find an Expense"
        query = params[:q].to_s.strip
        return if query.blank?

        expense = lookup_expense(query)
        if expense
          redirect_to edit_admin_reimbursements_expense_edit_path(expense.record_id)
        else
          flash.now[:alert] = "No expense matches \"#{query}\". Try its number (e.g. 42) or record id."
        end
      end

      def edit
        load_edit(find_expense!)
      end

      def update
        expense = find_expense!
        error = ::Reimbursements::AmountValidation.error_for(
          amount: params[:amount], amount_excl_vat: params[:amount_excl_vat]
        ) || bank_detail_override_error
        if error
          load_edit(expense)
          flash.now[:alert] = error
          render :edit, status: :unprocessable_content
          return
        end

        store.update_expense!(expense.record_id, update_attrs)
        redirect_to_edit(expense, notice: "Saved changes to ##{expense.auto_number}.")
      end

      def add_receipts
        expense = find_expense!
        files = Array(params[:receipts]).compact_blank.select do |file|
          file.size <= ::Reimbursements::ExpenseForm::MAX_RECEIPT_BYTES &&
            ::Reimbursements::ReceiptContentType.allowed_upload?(file)
        end
        if files.empty?
          redirect_to_edit(expense, alert: "No usable receipt files (PDF or image, under the size limit).")
          return
        end

        files.each do |file|
          store.attach_receipt!(expense.record_id, filename: file.original_filename,
                                                   content_type: file.content_type, bytes: file.read)
        end
        redirect_to_edit(expense, notice: "Attached #{files.size} receipt(s) to ##{expense.auto_number}.")
      rescue ::Reimbursements::Airtable::Error => e
        redirect_to_edit(expense, alert: "Couldn't attach the receipt: #{e.message}")
      end

      def remove_receipt
        expense = find_expense!
        store.remove_receipt!(expense.record_id, params[:attachment_id])
        redirect_to_edit(expense, notice: "Removed a receipt from ##{expense.auto_number}.")
      rescue ::Reimbursements::Store::LastReceiptError
        redirect_to_edit(expense, alert: "Can't remove the last receipt from a submitted expense.")
      rescue ::Reimbursements::Airtable::Error => e
        redirect_to_edit(expense, alert: "Couldn't remove the receipt: #{e.message}")
      end

      private

      # Set the instance vars the edit view needs, shared by #edit and the
      # invalid-#update re-render. Reasons the expense needs attention need the
      # full budget set keyed by record id (over-budget check); modulus_checker
      # is a helper_method.
      def load_edit(expense)
        @expense = expense
        @title = "Edit ##{expense.auto_number}"
        @budgets = store.active_budgets
        @budget_by_id = store.budgets.index_by(&:record_id)
        @attention_reasons =
          ::Reimbursements::ReviewSupport.needs_attention_reasons(expense, @budget_by_id, modulus_checker)
      end

      def modulus_checker
        @modulus_checker ||= checker_builder.call
      end

      # All expenses, newest first, narrowed by the status/budget/attention
      # filters and the free-text search. Filtering happens in Ruby over the one
      # cached list (Airtable free plan — no per-filter API calls).
      def filtered_expenses
        result = store.expenses.sort_by { |e| e.submitted_at || Time.zone.at(0) }.reverse
        result = result.select { |e| e.status == @status_filter } if @status_filter.present?
        result = result.select { |e| e.budget&.record_id == @budget_filter } if @budget_filter.present?
        if @attention_only
          result = result.select do |e|
            ::Reimbursements::ReviewSupport.needs_attention(e, @budget_by_id, modulus_checker)
          end
        end
        result = result.select { |e| matches_query?(e, @query) } if @query.present?
        result
      end

      # The filtered expenses as a CSV string: one header row then a row per
      # expense, using the effective payee (the money path) and the same
      # needs-attention reasons the table shows. Amounts stay as plain numbers so
      # the export is spreadsheet-friendly; the submitted date is ISO 8601.
      CSV_HEADERS = [ "#", "Status", "Payee", "Budget", "Amount", "Amount ex VAT",
                      "Description", "Payment reference", "Submitted", "Needs attention" ].freeze

      def expenses_csv(expenses)
        CSV.generate do |csv|
          csv << CSV_HEADERS
          expenses.each do |expense|
            reasons = ::Reimbursements::ReviewSupport.needs_attention_reasons(expense, @budget_by_id, modulus_checker)
            csv << [
              expense.auto_number, expense.status, expense.effective_payee_name,
              expense.budget&.name, expense.amount, expense.amount_excl_vat,
              expense.description, expense.payment_reference,
              helpers.reimbursements_date(expense.submitted_at), reasons.join("; ")
            ]
          end
        end
      end

      # Case-insensitive substring over description, effective payee name and
      # payment reference; an exact match on the visible auto-number; or a
      # numeric match on the gross amount.
      def matches_query?(expense, query)
        needle = query.downcase
        return true if expense.description.to_s.downcase.include?(needle)
        return true if expense.effective_payee_name.to_s.downcase.include?(needle)
        return true if expense.payment_reference.to_s.downcase.include?(needle)
        return true if expense.auto_number.to_s == query.sub(/\A#/, "")

        amount_matches?(expense.amount, query)
      end

      def amount_matches?(amount, query)
        return false if amount.nil?

        Float(query.delete("£, ")) == amount.to_f
      rescue ArgumentError
        false
      end

      def find_expense!
        expense = store.find_expense!(params[:id])
        raise ActiveRecord::RecordNotFound if expense.nil?

        expense
      end

      # Match on Airtable record id first, then on the visible auto-number.
      def lookup_expense(query)
        by_id = store.find_expense(query)
        return by_id if by_id

        store.expenses.find { |e| e.auto_number.to_s == query.sub(/\A#/, "") }
      end

      def update_attrs
        attrs = {
          amount: params[:amount].presence,
          description: params[:description],
          payment_reference: params[:payment_reference],
          nominal_code_override: params[:nominal_code_override].to_s,
          budget_record_id: params[:budget_record_id].presence,
          payee_name_override: params[:payee_name_override].to_s,
          # Persist the SAME normalized value #bank_detail_override_error just
          # validated (dashed sort code, whitespace-stripped account number) —
          # so what's validated and what later reaches the BACS spreadsheet
          # are always the identical string, matching ExpenseForm's pattern.
          sort_code_override: ::Reimbursements::BankDetails.format_sort_code(params[:sort_code_override].to_s),
          account_number_override:
            ::Reimbursements::BankDetails.normalize_account_number(params[:account_number_override].to_s)
        }
        # Only write excl-VAT when a positive value is given (0 means "not yet
        # known", leave the field alone), mirroring the Review save.
        excl_vat = params[:amount_excl_vat].to_f
        attrs[:amount_excl_vat] = excl_vat if excl_vat.positive?
        attrs
      end

      # Only validates a field's format when it's actually present — a blank
      # override means "no override, fall back to the payee's own bank
      # details," same as ExpenseForm#overrides_valid. Unlike every other
      # bank-detail write path in this diff, this finance-only "Edit (any
      # status)" form previously wrote raw params with zero format check.
      #
      # Also requires the three override fields to be all-or-nothing: setting
      # only a sort code (or only an account number) would splice a third
      # party's partial bank details onto the payee's own remaining fields —
      # an internally-inconsistent pair that still passes each field's own
      # format check in isolation.
      def bank_detail_override_error
        payee_name = params[:payee_name_override].to_s
        sort_code = params[:sort_code_override].to_s
        account_number = params[:account_number_override].to_s

        if sort_code.present? && !::Reimbursements::BankDetails.valid_sort_code?(sort_code)
          return "Sort code override #{::Reimbursements::BankDetails::SORT_CODE_HINT}"
        end
        if account_number.present? && !::Reimbursements::BankDetails.valid_account_number?(account_number)
          return "Account number override #{::Reimbursements::BankDetails::ACCOUNT_NUMBER_HINT}"
        end

        overrides = [ payee_name, sort_code, account_number ]
        if overrides.any?(&:present?) && !overrides.all?(&:present?)
          return "To pay a third party, fill in all three overrides: payee name, sort code, " \
                 "and account number — not just one or two."
        end

        nil
      end

      def redirect_to_edit(expense, flash)
        redirect_to edit_admin_reimbursements_expense_edit_path(expense.record_id), **flash
      end
    end
  end
end
