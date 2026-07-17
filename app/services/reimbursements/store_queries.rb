module Reimbursements
  ##
  # The read-side filters both stores share: pure-Ruby lookups over the
  # memoized lists (+expenses+, +people+, +budgets+, +batches+,
  # +eusa_actuals+) each backend loads its own way. Keeping them in one
  # module guarantees the Airtable and database backends answer identically
  # during the cutover window. Includers provide the list readers and
  # +fetch_expense+ (the by-id fallback for a stale memoized list).
  module StoreQueries
    def expenses_for(person_record_id)
      return [] if person_record_id.blank?

      expenses.select { |e| e.person&.record_id == person_record_id }
              .sort_by { |e| e.submitted_at || Time.zone.at(0) }
              .reverse
    end

    def find_expense(record_id)
      expenses.find { |e| e.record_id == record_id.to_s }
    end

    # By-id lookup that survives a stale memoized list (e.g. the expense was
    # created by the poll job in another process): on a miss it fetches the
    # single record fresh and folds it into this instance.
    def find_expense!(record_id)
      find_expense(record_id) || fetch_expense(record_id)
    end

    def person_by_email(email)
      return nil if email.blank?

      people.find { |p| p.email.to_s.strip.casecmp?(email.strip) }
    end

    def find_person(record_id)
      people.find { |p| p.record_id == record_id.to_s }
    end

    # Budgets a submitter may charge an expense to.
    def active_budgets
      budgets.select { |b| b.active && !b.income? }.sort_by(&:name)
    end

    def find_budget(record_id)
      budgets.find { |b| b.record_id == record_id.to_s }
    end

    def find_batch(record_id)
      batches.find { |b| b.record_id == record_id.to_s }
    end

    # Actuals imported for a given EUSA period (P1..P12, the raw period
    # string from the export), used to dedup a freshly-pasted export against
    # what's already stored for that period.
    def actuals_for_period(period)
      eusa_actuals.select { |a| a.period == period }
    end
  end
end
