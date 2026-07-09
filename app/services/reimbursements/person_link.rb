module Reimbursements
  ##
  # Resolves a Black Lightning user to their Airtable People record (the payee
  # registry): stored link first, then email match (persisted for next time),
  # and — on first submission — creates the People record.
  class PersonLink
    def initialize(store:)
      @store = store
    end

    def person_for(user)
      if user.airtable_person_id.present?
        person = @store.find_person(user.airtable_person_id)
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

    def remember_link(user, person)
      # Link cache only — deliberately skips validations/callbacks so legacy
      # user records that no longer validate can still use the portal.
      user.update_column(:airtable_person_id, person.record_id) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
