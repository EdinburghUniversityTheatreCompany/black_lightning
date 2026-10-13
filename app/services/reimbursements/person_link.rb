module Reimbursements
  ##
  # Resolves a user to their payee (People) record: the stored link
  # (users.reimbursements_person_id), then email match (remembered), else creates one.
  class PersonLink
    def initialize(store:)
      @store = store
    end

    def person_for(user)
      stored = user.reimbursements_person_id
      if stored.present?
        person = @store.find_person(stored)
        return person if person
      end

      match = @store.person_by_email(user.email)
      remember!(user, match) if match
      match
    end

    def ensure_person!(user)
      person_for(user) || create_person(user)
    end

    private

    def create_person(user)
      person = @store.create_person!(name: user.full_name.presence || user.email, email: user.email)
      remember!(user, person)
      person
    end

    # update_column: a legacy user that no longer validates must still reach the portal.
    def remember!(user, person)
      user.update_column(:reimbursements_person_id, person.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
