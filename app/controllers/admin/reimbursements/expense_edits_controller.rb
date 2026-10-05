module Admin
  module Reimbursements
    ##
    # Finance editing of one expense at ANY status. There is deliberately no
    # +editable?+ guard: that belongs to the producer portal.
    class ExpenseEditsController < FinanceController
      include AttachesReceipts

      def index
        @title = "Expenses"
        @statuses = ::Reimbursements::Status.all
        @budgets = store.budgets.sort_by { |b| b.display_name.to_s }
        @budget_by_id = store.budgets.index_by(&:record_id)

        @status_filter = params[:status].to_s.strip
        @budget_filter = params[:budget].to_s.strip
        # The SUBMITTER's record id (People's "N claims" link), so two people
        # sharing a name are two lists.
        @person_filter = params[:person].to_s.strip
        @person = store.people.find { |p| p.record_id == @person_filter } if @person_filter.present?
        @query = params[:q].to_s.strip
        @attention_only = params[:attention] == "1"

        filtered = filtered_expenses
        respond_to do |format|
          format.html { @expenses = paginate(filtered) }
          # The full filtered set: pagination is display-only.
          format.csv { send_export ::Reimbursements::Exports::Expenses, filtered }
        end
      end

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
        error = amount_error(expense) || foreign_amount_error(expense) ||
                bank_detail_override_error(expense) || expense_type_error(expense) ||
                budget_record_id_error(params[:budget_record_id]) ||
                person_record_id_error(params[:person_record_id])
        if error
          load_edit(expense)
          flash.now[:alert] = error
          render :edit, status: :unprocessable_content
          return
        end

        store.update_expense!(expense.record_id, update_attrs(expense))
        redirect_to_edit(expense, notice: "Saved changes to ##{expense.auto_number}.")
      end

      # Back to PENDING, never Approved, so the claim re-enters the owner gate
      # and reopening is no way round a sign-off. The rejection reason and stamp
      # are kept as history. Nobody is emailed: the operator tells the producer
      # in the reply they are already writing.
      def reopen
        expense = find_expense!
        unless expense.status == ::Reimbursements::Status::REJECTED
          redirect_to_edit(expense, alert: "Only a rejected claim can be reopened. " \
                                           "##{expense.auto_number} is #{expense.status}.")
          return
        end

        store.update_expense!(expense.record_id, status: ::Reimbursements::Status::PENDING)
        redirect_to_edit(expense,
                         notice: "##{expense.auto_number} is Pending again and back in the review " \
                                 "queue. Nobody was emailed, and the rejection is kept in its " \
                                 "history.")
      end

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

      # Shared by #edit and the invalid-#update re-render.
      def load_edit(expense)
        @expense = expense
        @title = "Edit ##{expense.auto_number}"
        @budgets = store.active_budgets
        @budget_by_id = store.budgets.index_by(&:record_id)
        @people = store.people_in_name_order
        @attention =
          ::Reimbursements::ReviewSupport.attention_summary(expense, @budget_by_id, modulus_checker)
        load_history(expense)
      end

      # The History card: endorsement and batch, one row each.
      def load_history(expense)
        @endorsement = store.endorsement_for_expense(expense.record_id)
        @endorsing_person =
          store.people.find { |p| p.record_id == @endorsement.endorsed_by_person_id } if
            @endorsement&.owner_endorsement?
        @batch = store.find_batch(expense.batch_id.to_s) if expense.batch_id.present?
      end

      # Newest first, filtered in Ruby over the store's one memoized list.
      def filtered_expenses
        result = store.expenses.sort_by { |e| e.submitted_at || Time.zone.at(0) }.reverse
        result = result.select { |e| e.status == @status_filter } if @status_filter.present?
        result = result.select { |e| e.budget&.record_id == @budget_filter } if @budget_filter.present?
        result = result.select { |e| e.person&.record_id == @person_filter } if @person_filter.present?
        if @attention_only
          result = result.select do |e|
            ::Reimbursements::ReviewSupport.needs_attention(e, @budget_by_id, modulus_checker)
          end
        end
        result = result.select { |e| matches_query?(e, @query) } if @query.present?
        result
      end

      # The submitter as well as the effective payee: on an Invoice the payee is
      # the supplier, and the producer chasing it searches by their own name.
      def matches_query?(expense, query)
        needle = query.downcase
        return true if expense.description.to_s.downcase.include?(needle)
        return true if expense.effective_payee_name.to_s.downcase.include?(needle)
        return true if expense.person&.name.to_s.downcase.include?(needle)
        return true if expense.person&.email.to_s.downcase.include?(needle)
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

      # Record id first, then the visible auto-number.
      def lookup_expense(query)
        store.find_expense(query) ||
          store.expenses.find { |e| e.auto_number.to_s == query.sub(/\A#/, "") }
      end

      # Every rail-aware rule reads the rail being POSTED, not the stored one,
      # or it would check the overrides being left behind instead of the ones
      # just typed.
      def posted_rail_international?(expense)
        return expense.international? unless rail_editable?(expense)

        rail = params[:payment_method].to_s
        return expense.international? unless ::Reimbursements::Expense::PAYMENT_METHODS.include?(rail)

        rail == ::Reimbursements::Expense::PAYMENT_METHOD_INTERNATIONAL
      end

      # The posted payee must be one the page rendered, or the foreign key 500s.
      # Deliberately not narrowed by status: imported claims already Paid to
      # the wrong payee are what this exists to correct.
      def person_record_id_error(record_id)
        return nil if record_id.blank?
        return nil if store.people_in_name_order.any? { |person| person.record_id == record_id.to_s }

        "That person is no longer in the registry. Reload the page and pick again."
      end

      # The rail is fixed once Submitted or Paid: the paperwork has gone out.
      def rail_editable?(expense)
        ::Reimbursements::ReviewSupport.attention_actionable?(expense)
      end
      helper_method :rail_editable?

      # A blank GBP amount is legitimate on the international rail (finance types
      # it at review). Blank means leave it alone: update_expense! compacts nil.
      def amount_error(expense)
        blank_gross = params[:amount].to_s.strip.blank?
        return nil if blank_gross && posted_rail_international?(expense)

        ::Reimbursements::AmountValidation.error_for(
          amount: params[:amount], amount_excl_vat: params[:amount_excl_vat]
        )
      end

      # Blank clears the invoice figure (approval already blocks on a missing
      # one); anything unreadable is refused with the field named.
      def foreign_amount_error(expense)
        return nil unless posted_rail_international?(expense)

        raw = params[:foreign_amount]
        return nil if raw.nil? || raw.to_s.strip.blank?

        parsed = ::Reimbursements::AmountParser.parse(raw)
        return nil if parsed&.positive?

        "Invoice amount: enter a number greater than 0, or leave it blank."
      end

      # A rail switch changes payment_method only. The other rail's encrypted
      # overrides are inert and kept, since wiping them is unrecoverable; ex-VAT
      # is mirrored by the model.
      def rail_attrs(expense)
        return {} unless rail_editable?(expense)

        rail = params[:payment_method].to_s
        return {} unless ::Reimbursements::Expense::PAYMENT_METHODS.include?(rail)

        { payment_method: rail }
      end

      def update_attrs(expense)
        attrs = {
          # The parsed BigDecimal, never the raw field: AR casts "£1,200" to 0.
          amount: ::Reimbursements::AmountValidation.amount(params[:amount]),
          description: params[:description],
          payment_reference: params[:payment_reference],
          expense_type: params[:expense_type],
          nominal_code_override: params[:nominal_code_override].to_s,
          budget_record_id: params[:budget_record_id].presence,
          # Blank is compacted away, never unlinking the claim from its person:
          # the BACS pre-flight refuses a payee-less claim.
          person_record_id: params[:person_record_id].presence,
          payee_name_override: params[:payee_name_override].to_s,
          # Store the same normalised strings #bank_detail_override_error validated.
          sort_code_override: ::Reimbursements::BankDetails.format_sort_code(params[:sort_code_override].to_s),
          account_number_override:
            ::Reimbursements::BankDetails.normalize_account_number(params[:account_number_override].to_s),
          iban_override: ::Reimbursements::BankDetails.normalize_iban(params[:iban_override].to_s),
          bic_override: ::Reimbursements::BankDetails.normalize_bic(params[:bic_override].to_s)
        }
        # International only, so a UK post never blanks stored figures the claim
        # gets back if switched again.
        if posted_rail_international?(expense)
          attrs[:foreign_currency] = params[:foreign_currency].to_s.strip.upcase
        end
        attrs.merge!(rail_attrs(expense))
        if posted_rail_international?(expense)
          attrs[:foreign_amount] = ::Reimbursements::AmountValidation.amount(params[:foreign_amount])
        end
        # Blank or 0 means "not yet known": leave the stored value alone.
        excl_vat = ::Reimbursements::AmountValidation.amount_excl_vat(params[:amount_excl_vat])
        attrs[:amount_excl_vat] = excl_vat if excl_vat
        attrs
      end

      # Formats are checked only when present (blank falls back to the payee's
      # own details). The trio is all-or-nothing, or a third party's partial
      # details would be spliced onto the payee's.
      def bank_detail_override_error(expense)
        payee_name = params[:payee_name_override].to_s
        if payee_name.length > ::Reimbursements::BankDetails::PAYEE_NAME_MAX_LENGTH
          return "Payee name override #{::Reimbursements::BankDetails::PAYEE_NAME_HINT}"
        end

        if posted_rail_international?(expense)
          international_override_error(payee_name)
        else
          uk_override_error(payee_name)
        end
      end

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

      # ExpenseForm's Invoice rule, only while the money can still move:
      # Submitted and Paid claims stay re-typable without invented bank details.
      def expense_type_error(expense)
        type = params[:expense_type].to_s
        return nil if type.blank?
        return "Unknown expense type." unless ::Reimbursements::Expense::TYPES.include?(type)
        return nil unless type == ::Reimbursements::Expense::TYPE_INVOICE
        return nil unless ::Reimbursements::ReviewSupport.attention_actionable?(expense)

        international = posted_rail_international?(expense)
        second, third =
          if international
            [ params[:iban_override].to_s, params[:bic_override].to_s ]
          else
            [ params[:sort_code_override].to_s, params[:account_number_override].to_s ]
          end
        unless ::Reimbursements::BankDetails.overrides_missing?(
          params[:payee_name_override].to_s, second, third
        )
          return nil
        end

        fields = international ? "name, IBAN and BIC" : "name, sort code and account number"
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
