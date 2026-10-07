module Admin
  module Reimbursements
    ##
    # Finance-team management of the People registry: duplicate banner, live
    # modulus badge, inline bank-detail editing with an audit line in the notes,
    # Mark verified, and registering an existing user as a payee.
    class PeopleController < FinanceController
      before_action -> { @query = params[:q].to_s.strip }, only: %i[index update]

      def index
        respond_to do |format|
          format.html { load_registry }
          # The on-screen filter carries through; bank details are masked (Exports::People).
          format.csv do
            send_export ::Reimbursements::Exports::People,
                        filtered_people(store.people_in_name_order)
          end
        end
      end

      def new
        @title = "Register a person"
      end

      # No bank details are collected: a budget owner may never claim, and
      # finance must be able to name one who has never saved details.
      def create
        user = ::User.find_by(id: params[:user_id])
        if user.nil?
          @title = "Register a person"
          @error = "Pick a user account to register."
          return render :new, status: :unprocessable_entity
        end

        # PersonLink resolves by stored link THEN email, so this also catches
        # someone held under their address but never linked.
        existing = person_link.person_for(user)
        return redirect_to_existing(user, existing) if existing

        person = person_link.ensure_person!(user)
        redirect_to admin_reimbursements_people_path,
                    notice: "#{person.name} is now in the registry. They can be given a budget " \
                            "to own; bank details are only needed if they claim."
      end

      def update
        @person = find_or_404(:find_person)

        params[:verify].present? ? mark_verified : save_bank_details
      end

      private

      # Names the record they resolved to rather than minting a duplicate.
      def redirect_to_existing(user, person)
        redirect_to admin_reimbursements_people_path,
                    alert: "#{user.name_or_email} is already in the registry as " \
                           "#{person.name.presence || person.email}."
      end

      def load_registry
        @title = "Reimbursements People"
        people = store.people_in_name_order
        # Over the WHOLE registry, not the filtered page: a filter hiding one
        # half of a pair would hide the warning too.
        @duplicates = ::Reimbursements::PeopleSupport.find_duplicate_people(people)
        @claim_counts = store.expense_counts_by_person_id
        # The row to open: the one just saved, or linked to from a Review card.
        @open_person_id = @edit_person_id || params[:person].to_s.presence
        filtered = filtered_people(people)
        @people = paginate(filtered, page: registry_page(filtered))
      end

      # The page holding the open row, so it is on screen when it sits past the
      # first page; an explicit ?page= wins.
      def registry_page(filtered)
        return params[:page] if params[:page].present? || @open_person_id.blank?

        position = filtered.index { |person| person.record_id == @open_person_id }
        position ? (position / PAGE_SIZE) + 1 : params[:page]
      end

      # Name or email, case-insensitive substring, over the store's memoized list.
      def filtered_people(people)
        return people if @query.blank?

        needle = @query.downcase
        people.select do |person|
          person.name.to_s.downcase.include?(needle) || person.email.to_s.downcase.include?(needle)
        end
      end

      # Back to the registry with this person's row open and scrolled to.
      def redirect_to_person(person, flash)
        redirect_to admin_reimbursements_people_path(person: person.record_id, q: params[:q].presence,
                                                     anchor: "person-#{person.record_id}"),
                    **flash
      end

      def mark_verified
        unless @person.bank_details?
          redirect_to_person(@person, alert: "#{@person.name} has no bank details to verify.")
          return
        end

        # bank_details? is presence only. Gate on the same modulus check the
        # live badge shows, so "Verified" can't contradict the screen.
        if modulus_checker.check(@person.sort_code, @person.account_number) == ::Reimbursements::ModulusCheck::INVALID
          redirect_to_person(@person,
                             alert: "#{@person.name}'s bank details fail the modulus check. Fix them " \
                                    "before marking as verified.")
          return
        end

        store.update_person!(@person.record_id, verified: true)
        redirect_to_person(@person, notice: "#{@person.name} marked as verified.")
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

        change = @person.bank_details_change(formatted_sort, normalized_account, actor: current_user)
        if change.nil?
          redirect_to_person(@person, notice: "No changes to save.")
          return
        end

        store.update_person!(@person.record_id, **change)
        redirect_to_person(@person, notice: "Bank details saved for #{@person.name}.")
      end

      # Re-renders (not redirects) so the row stays open with the typed values.
      def render_bank_details_error(sort_code, account_number, message)
        @edit_person_id = @person.record_id
        @edit_sort_code = sort_code
        @edit_account_number = account_number
        @edit_error = message
        load_registry
        render :index, status: :unprocessable_entity
      end

      def valid_bank_details?(sort_code, account_number)
        ::Reimbursements::BankDetails.valid_sort_code?(sort_code) &&
          ::Reimbursements::BankDetails.valid_account_number?(account_number)
      end
    end
  end
end
