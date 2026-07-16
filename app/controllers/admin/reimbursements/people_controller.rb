module Admin
  module Reimbursements
    ##
    # Finance-team management of the Airtable People registry (payee names,
    # emails, bank details). Ports bedlam-bacs `pages/5_People.py`: a duplicate
    # name/email banner, a live modulus badge on each person's bank details,
    # inline editing of sort code / account number (with a timestamped audit
    # line appended to notes), and a Mark-verified action.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`),
    # distinct from the producer portal's `:access, :reimbursements`.
    class PeopleController < FinanceController
      def index
        @title = "Reimbursements People"
        load_registry
      end

      def update
        @person = find_or_404(:find_person)

        params[:verify].present? ? mark_verified : save_bank_details
      end

      private

      def load_registry
        people = store.people
        # Duplicate detection runs over the WHOLE registry, not just one page.
        @duplicates = ::Reimbursements::PeopleSupport.find_duplicate_people(people)
        @people = paginate(people)
      end

      def mark_verified
        unless @person.bank_details?
          redirect_to admin_reimbursements_people_path,
                      alert: "#{@person.name} has no bank details to verify."
          return
        end

        # bank_details? is pure presence — it says nothing about whether the
        # sort code/account number are actually mathematically consistent.
        # Gate on the same modulus check the page's own live badge renders
        # right next to this button, so "Verified" can't contradict what the
        # operator can see on the same screen.
        if modulus_checker.check(@person.sort_code, @person.account_number) == ::Reimbursements::ModulusCheck::INVALID
          redirect_to admin_reimbursements_people_path,
                      alert: "#{@person.name}'s bank details fail the modulus check — fix them " \
                             "before marking as verified."
          return
        end

        store.update_person!(@person.record_id, verified: true)
        redirect_to admin_reimbursements_people_path, notice: "#{@person.name} marked as verified."
      end

      def save_bank_details
        sort_code = params[:sort_code].to_s
        account_number = params[:account_number].to_s

        unless valid_bank_details?(sort_code, account_number)
          render_bank_details_error(
            sort_code, account_number,
            "Sort code #{::Reimbursements::BankDetails::SORT_CODE_HINT} " \
            "Account number #{::Reimbursements::BankDetails::ACCOUNT_NUMBER_HINT}"
          )
          return
        end

        formatted_sort = ::Reimbursements::BankDetails.format_sort_code(sort_code)
        normalized_account = ::Reimbursements::BankDetails.normalize_account_number(account_number)

        unless bank_details_changed?(formatted_sort, normalized_account)
          redirect_to admin_reimbursements_people_path, notice: "No changes to save."
          return
        end

        store.update_person!(@person.record_id,
                             sort_code: formatted_sort,
                             account_number: normalized_account,
                             # The "Verified" badge is a trust signal that's only ever meaningful
                             # for the bank details it was checked against — a correction (typo
                             # fix, bank switch) must not leave a stale "Verified" claim standing
                             # over details nobody has actually re-checked.
                             verified: false,
                             notes: appended_notes(formatted_sort, normalized_account))
        redirect_to admin_reimbursements_people_path,
                    notice: "Bank details saved for #{@person.name}."
      end

      # Re-render the registry with this person's edit section expanded, the
      # operator's typed (invalid) values still in the fields, and the error
      # shown inline — rather than redirecting, which would collapse the
      # <details> and discard what they typed.
      def render_bank_details_error(sort_code, account_number, message)
        @title = "Reimbursements People"
        load_registry
        @edit_person_id = @person.record_id
        @edit_sort_code = sort_code
        @edit_account_number = account_number
        @edit_error = message
        render :index, status: :unprocessable_entity
      end

      def valid_bank_details?(sort_code, account_number)
        ::Reimbursements::BankDetails.valid_sort_code?(sort_code) &&
          ::Reimbursements::BankDetails.valid_account_number?(account_number)
      end

      def bank_details_changed?(formatted_sort, normalized_account)
        formatted_sort != @person.sort_code ||
          normalized_account != ::Reimbursements::BankDetails.normalize_account_number(@person.account_number)
      end

      # Timestamped audit line appended to the person's notes on every bank
      # detail change, mirroring bedlam-bacs `5_People.py` (`_audit_line` /
      # `_append_note`): existing notes are preserved, one line per change.
      def appended_notes(sort_code, account_number)
        timestamp = Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")
        audit_line = "[#{timestamp}] Bank details updated: sort code #{sort_code}, account #{account_number}"
        existing = @person.notes.to_s
        existing.strip.empty? ? audit_line : "#{existing.rstrip}\n#{audit_line}"
      end
    end
  end
end
