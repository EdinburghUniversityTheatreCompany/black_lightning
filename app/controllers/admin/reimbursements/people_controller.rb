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
      # Injection seam for tests: the modulus checker (loaded from the vendored
      # Pay.UK rule files in production; a fake in functional tests so badge
      # states don't depend on gitignored data being present).
      class_attribute :checker_builder, default: -> { ::Reimbursements::ModulusCheck.default_checker }

      helper_method :modulus_checker

      def index
        @title = "Reimbursements People"
        @people = store.people
        @duplicates = ::Reimbursements::PeopleSupport.find_duplicate_people(@people)
      end

      def update
        @person = store.find_person(params[:id])
        raise ActiveRecord::RecordNotFound if @person.nil?

        params[:verify].present? ? mark_verified : save_bank_details
      end

      private

      def modulus_checker
        @modulus_checker ||= checker_builder.call
      end

      def mark_verified
        unless @person.bank_details?
          redirect_to admin_reimbursements_people_path,
                      alert: "#{@person.name} has no bank details to verify."
          return
        end

        store.update_person!(@person.record_id, verified: true)
        redirect_to admin_reimbursements_people_path, notice: "#{@person.name} marked as verified."
      end

      def save_bank_details
        sort_code = params[:sort_code].to_s
        account_number = params[:account_number].to_s

        unless valid_bank_details?(sort_code, account_number)
          redirect_to admin_reimbursements_people_path,
                      alert: "Sort code #{::Reimbursements::BankDetails::SORT_CODE_HINT} " \
                             "Account number #{::Reimbursements::BankDetails::ACCOUNT_NUMBER_HINT}"
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
                             notes: appended_notes(formatted_sort, normalized_account))
        redirect_to admin_reimbursements_people_path,
                    notice: "Bank details saved for #{@person.name}."
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
