module Reimbursements
  ##
  # Duplicate detection for the People page: a person is a duplicate when another
  # shares their non-empty name or email (case-insensitive, trimmed).
  module PeopleSupport
    module_function

    # Returns the subset of +people+ involved in at least one name/email clash,
    # in original order, each person at most once.
    def find_duplicate_people(people)
      counts = people.flat_map { |person| duplicate_keys(person) }.tally
      people.select { |person| duplicate_keys(person).any? { |key| counts[key] > 1 } }
    end

    def duplicate_keys(person)
      { name: person.name, email: person.email }
        .filter_map { |field, value| [ field, value.strip.downcase ] if value.present? }
    end
  end
end
