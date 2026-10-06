module Reimbursements
  ##
  # Resolves a user to their payee (People) record: stored link, then email match
  # (remembered), else creates one. Which users column holds the link is the
  # STORE's knowledge, so a PersonLink can never pair a store with the wrong one.
  class PersonLink
    def initialize(store:)
      @store = store
    end

    def person_for(user)
      stored = @store.stored_person_link(user)
      if stored.present?
        person = @store.find_person(stored)
        return person if person
      end

      match = @store.person_by_email(user.email)
      @store.remember_person_link!(user, match) if match
      match
    end

    def ensure_person!(user)
      person_for(user) || create_person(user)
    end

    private

    def create_person(user)
      person = @store.create_person!(name: user.full_name.presence || user.email, email: user.email)
      @store.remember_person_link!(user, person)
      person
    end
  end
end
