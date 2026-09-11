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
    # lookup by auto-number or record id (so a Submitted/Paid expense
    # that never appears on the Review tabs can still be found). Edits persist
    # through +store.update_expense!+, which is status-agnostic; a Submitted or
    # Paid expense shows a clear note that the edit won't change what EUSA has
    # already processed.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class ExpenseEditsController < FinanceController
      include AttachesReceipts

      # All expenses as a filterable/searchable table, newest first, each row
      # opening the edit page above. The finance team's primary way in — the
      # old +find+ lookup is now just the search box on this page.
      def index
        @title = "Expenses"
        @statuses = ::Reimbursements::Status.all
        @budgets = store.budgets.sort_by { |b| b.display_name.to_s }
        @budget_by_id = store.budgets.index_by(&:record_id)

        @status_filter = params[:status].to_s.strip
        @budget_filter = params[:budget].to_s.strip
        @query = params[:q].to_s.strip
        @attention_only = params[:attention] == "1"

        filtered = filtered_expenses
        respond_to do |format|
          # The whole list is already loaded and filtered in Ruby, so paginate
          # the array rather than re-querying.
          format.html { @expenses = paginate(filtered) }
          # Export the FULL filtered set (the on-screen filters carry through the
          # query string) — pagination is display-only, so the CSV isn't paged.
          format.csv { send_export ::Reimbursements::Exports::Expenses, filtered }
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
        ) || bank_detail_override_error(expense) || expense_type_error(expense) ||
              budget_record_id_error(params[:budget_record_id])
        if error
          load_edit(expense)
          flash.now[:alert] = error
          render :edit, status: :unprocessable_content
          return
        end

        store.update_expense!(expense.record_id, update_attrs)
        redirect_to_edit(expense, notice: "Saved changes to ##{expense.auto_number}.")
      end

      # Both answer a turbo stream for the receipts-upload dropzone on the edit
      # page (replacing the gallery in place) and redirect for a plain post.
      def add_receipts
        expense = find_expense!
        attached, upload_errors = attach_posted_receipts(expense)
        if attached.zero? && upload_errors.empty?
          upload_errors = [ NOTHING_USABLE ]
        end
        notice = "Attached #{attached} receipt(s) to ##{expense.auto_number}." if attached.positive?
        respond_with_finance_gallery(expense, upload_errors: upload_errors, notice: notice)
      rescue StandardError => e # AR/ActiveStorage failures
        raise if expense.nil?

        respond_with_finance_gallery(expense, upload_errors: [ "Couldn't attach the receipt: #{e.message}" ])
      end

      def remove_receipt
        expense = find_expense!
        store.remove_receipt!(expense.record_id, params[:attachment_id])
        respond_with_finance_gallery(expense, notice: "Removed a receipt from ##{expense.auto_number}.")
      rescue ::Reimbursements::DatabaseStore::LastReceiptError
        respond_with_finance_gallery(expense, upload_errors: [ "Can't remove the last receipt from a submitted expense." ])
      rescue StandardError => e
        raise if expense.nil?

        respond_with_finance_gallery(expense, upload_errors: [ "Couldn't remove the receipt: #{e.message}" ])
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
        @attention =
          ::Reimbursements::ReviewSupport.attention_summary(expense, @budget_by_id, modulus_checker)
      end

      # All expenses, newest first, narrowed by the status/budget/attention
      # filters and the free-text search. Filtering happens in Ruby over the
      # store's one memoized list, not as a query per filter.
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

      # Match on record id first, then on the visible auto-number. find_expense
      # coerces a non-numeric query to no match (nil) rather than raising.
      def lookup_expense(query)
        store.find_expense(query) ||
          store.expenses.find { |e| e.auto_number.to_s == query.sub(/\A#/, "") }
      end

      def update_attrs
        attrs = {
          # The parsed BigDecimal AmountValidation just approved, not the raw field:
          # AR would cast "£1,200" to 0 on the decimal column.
          amount: ::Reimbursements::AmountValidation.amount(params[:amount]),
          description: params[:description],
          payment_reference: params[:payment_reference],
          expense_type: params[:expense_type],
          nominal_code_override: params[:nominal_code_override].to_s,
          budget_record_id: params[:budget_record_id].presence,
          payee_name_override: params[:payee_name_override].to_s,
          # Persist the SAME normalized value #bank_detail_override_error just
          # validated (dashed sort code, whitespace-stripped account number) —
          # so what's validated and what later reaches the BACS spreadsheet
          # are always the identical string, matching ExpenseForm's pattern.
          sort_code_override: ::Reimbursements::BankDetails.format_sort_code(params[:sort_code_override].to_s),
          account_number_override:
            ::Reimbursements::BankDetails.normalize_account_number(params[:account_number_override].to_s),
          # Same rule as the pair above: store exactly the normalised string
          # #bank_detail_override_error validated, so what was checked and what
          # reaches EUSA's form are the identical value.
          iban_override: ::Reimbursements::BankDetails.normalize_iban(params[:iban_override].to_s),
          bic_override: ::Reimbursements::BankDetails.normalize_bic(params[:bic_override].to_s),
          foreign_currency: params[:foreign_currency].to_s.strip.upcase
        }
        # The invoice figure, which is what EUSA's bank actually pays. Written
        # only when a positive value is given, like excl-VAT below: a blank
        # means "not edited here", not "clear it".
        foreign = ::Reimbursements::AmountValidation.amount(params[:foreign_amount])
        attrs[:foreign_amount] = foreign if foreign&.positive?
        # Only write excl-VAT when a positive value is given (0 means "not yet
        # known", leave the field alone), mirroring the Review save.
        excl_vat = ::Reimbursements::AmountValidation.amount_excl_vat(params[:amount_excl_vat])
        attrs[:amount_excl_vat] = excl_vat if excl_vat
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
      def bank_detail_override_error(expense)
        payee_name = params[:payee_name_override].to_s
        if payee_name.length > ::Reimbursements::BankDetails::PAYEE_NAME_MAX_LENGTH
          return "Payee name override #{::Reimbursements::BankDetails::PAYEE_NAME_HINT}"
        end

        expense.international? ? international_override_error(payee_name) : uk_override_error(payee_name)
      end

      # The international rail routes on an IBAN and a BIC, so the UK trio rule
      # read fields it never fills: a claim with a payee name and no sort code
      # was refused outright, with a message naming fields that do not apply.
      def international_override_error(payee_name)
        iban = params[:iban_override].to_s
        bic = params[:bic_override].to_s

        unless ::Reimbursements::Expense::FOREIGN_CURRENCIES.include?(params[:foreign_currency].to_s.strip.upcase)
          return "Payment currency must be one of the currencies listed."
        end
        if iban.present? && !::Reimbursements::BankDetails.valid_iban?(iban)
          return "Payee IBAN #{::Reimbursements::BankDetails::IBAN_HINT}"
        end
        if bic.present? && !::Reimbursements::BankDetails.valid_bic?(bic)
          return "Payee BIC #{::Reimbursements::BankDetails::BIC_HINT}"
        end
        return nil unless ::Reimbursements::BankDetails.overrides_incomplete?(payee_name, iban, bic)

        "To pay someone abroad, fill in all three overrides: payee name, IBAN and BIC, " \
          "not just one or two."
      end

      def uk_override_error(payee_name)
        sort_code = params[:sort_code_override].to_s
        account_number = params[:account_number_override].to_s

        if sort_code.present? && !::Reimbursements::BankDetails.valid_sort_code?(sort_code)
          return "Sort code override #{::Reimbursements::BankDetails::SORT_CODE_HINT}"
        end
        if account_number.present? && !::Reimbursements::BankDetails.valid_account_number?(account_number)
          return "Account number override #{::Reimbursements::BankDetails::ACCOUNT_NUMBER_HINT}"
        end

        if ::Reimbursements::BankDetails.overrides_incomplete?(payee_name, sort_code, account_number)
          return "To pay a third party, fill in all three overrides: payee name, sort code, " \
                 "and account number, not just one or two."
        end

        nil
      end

      # ExpenseForm's Invoice rule (no override trio means EffectivePayee pays
      # the SUBMITTER) applies here too, but only while the money can still
      # move: Submitted and Paid record what EUSA already did, and a historical
      # row whose supplier details we never captured must stay re-typable
      # instead of demanding invented bank details.
      def expense_type_error(expense)
        type = params[:expense_type].to_s
        return nil if type.blank?
        return "Unknown expense type." unless ::Reimbursements::Expense::TYPES.include?(type)
        return nil unless type == ::Reimbursements::Expense::TYPE_INVOICE
        return nil unless ::Reimbursements::ReviewSupport.attention_actionable?(expense)

        second, third =
          if expense.international?
            [ params[:iban_override].to_s, params[:bic_override].to_s ]
          else
            [ params[:sort_code_override].to_s, params[:account_number_override].to_s ]
          end
        unless ::Reimbursements::BankDetails.overrides_missing?(
          params[:payee_name_override].to_s, second, third
        )
          return nil
        end

        fields = expense.international? ? "name, IBAN and BIC" : "name, sort code and account number"
        "An Invoice pays the supplier directly, so it needs the payee overrides: #{fields}. " \
          "Without them this would pay #{expense.person&.name.presence || 'the submitter'} " \
          "instead. Use Reimbursement if they paid the bill themselves."
      end

      def redirect_to_edit(expense, flash)
        redirect_to edit_admin_reimbursements_expense_edit_path(expense.record_id), **flash
      end

      def respond_with_finance_gallery(expense, upload_errors: [], notice: nil)
        respond_with_receipts_gallery(expense.record_id, expense: expense, upload_errors: upload_errors,
                                      notice: notice, finance: true,
                                      redirect_path: edit_admin_reimbursements_expense_edit_path(expense.record_id))
      end
    end
  end
end
