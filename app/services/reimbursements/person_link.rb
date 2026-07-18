module Reimbursements
  ##
  # Resolves a Black Lightning user to their payee (People) record: stored
  # link first, then email match (persisted for next time), and — on first
  # submission — creates the People record.
  #
  # Which users column holds the stored link is the STORE's knowledge
  # (stored_person_link / remember_person_link!), not a global setting: a
  # PersonLink can then never pair a store with the wrong column, however it
  # was built (the test seams inject stores directly).
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
