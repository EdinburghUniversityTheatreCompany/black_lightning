module Reimbursements
  ##
  # Pure duplicate-detection for the People management page. A person is a
  # duplicate when another record shares their non-empty name or email
  # (case-insensitive, whitespace-trimmed). Ported from bedlam-bacs
  # `people_helpers.py`.
  module PeopleSupport
    module_function

    # Returns the subset of +people+ involved in at least one name/email clash,
    # in original order, each person at most once.
    def find_duplicate_people(people)
      name_counts = Hash.new(0)
      email_counts = Hash.new(0)

      people.each do |person|
        name_counts[person.name.strip.downcase] += 1 if person.name.present?
        email_counts[person.email.strip.downcase] += 1 if person.email.present?
      end

      people.select do |person|
        name_dup = person.name.present? && name_counts[person.name.strip.downcase] > 1
        email_dup = person.email.present? && email_counts[person.email.strip.downcase] > 1
        name_dup || email_dup
      end
    end
  end
end
