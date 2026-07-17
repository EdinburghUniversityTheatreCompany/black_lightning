module Reimbursements
  ##
  # Resolves a Black Lightning user to their payee (People) record: stored
  # link first, then email match (persisted for next time), and — on first
  # submission — creates the People record.
  #
  # The stored link is backend-specific: users.reimbursements_person_id (a
  # real FK) on the database backend, the legacy users.airtable_person_id
  # string on the Airtable backend. The importer backfills the FK from the
  # string at cutover; the string column is retired with the Airtable layer.
  class PersonLink
    def initialize(store:, backend: Settings.backend)
      @store = store
      @database = backend == "database"
    end

    def person_for(user)
      stored = stored_link(user)
      if stored.present?
        person = @store.find_person(stored)
        return person if person
      end

      match = @store.person_by_email(user.email)
      remember_link(user, match) if match
      match
    end

    def ensure_person!(user)
      person_for(user) || create_person(user)
    end

    private

    def create_person(user)
      person = @store.create_person!(name: user.full_name.presence || user.email, email: user.email)
      remember_link(user, person)
      person
    end

    def stored_link(user)
      @database ? user.reimbursements_person_id&.to_s : user.airtable_person_id
    end

    def remember_link(user, person)
      # Link cache only — deliberately skips validations/callbacks so legacy
      # user records that no longer validate can still use the portal.
      if @database
        user.update_column(:reimbursements_person_id, person.id) # rubocop:disable Rails/SkipsModelValidations
      else
        user.update_column(:airtable_person_id, person.record_id) # rubocop:disable Rails/SkipsModelValidations
      end
    end
  end
end
