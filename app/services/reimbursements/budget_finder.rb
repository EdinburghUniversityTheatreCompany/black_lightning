module Reimbursements
  ##
  # The budget line for one (area, nominal code) — found where it exists,
  # created where it does not. Option D's end state: a show's Marketing and
  # Other lines carry the SAME nominal code, so the code alone cannot name a
  # line and the area is what qualifies it.
  #
  # A service over ActiveRecord, as AreaBackfill is: the lookup is one scoped
  # read the store has no reader for, while the WRITE goes through
  # DatabaseStore#find_or_create_budget_for_area!, which re-takes this same
  # match under the area's row lock.
  #
  # Worth knowing before wiring a caller to this: a line created inside an area
  # inherits the AREA's owners (Budget#owners), so its sign-off gate is the
  # area's — and an area naming nobody has no gate at all, so claims on a line
  # created under one reach finance unendorsed.
  module BudgetFinder
    class Error < StandardError; end

    # Two lines could be the answer, or one could be the answer and could
    # equally be a different account. Never a pick: a wrong one splits a show's
    # spend across two lines, or books it against another show's.
    class AmbiguousError < Error; end

    # The centre's chart of accounts does not list this code, so there is no
    # label to name a new line with — and a line named after the bare digits is
    # one nobody chose.
    class UnknownCodeError < Error; end

    # Retired (NominalCode#active false): the code has left the pickers and
    # stays to label the historical rows that carry it. Finding its line still
    # works; starting NEW spend under an account finance withdrew does not.
    class RetiredCodeError < Error; end

    # The area belongs to no cost centre yet, so there is no chart of accounts
    # to read a label from. A real state rather than a malformed call —
    # Area#cost_centre is optional, and a budget only ever inherits one by
    # Budget's before_validation filling a blank — and a different fix from
    # UnknownCodeError, by a different person: place the area, rather than add
    # a code to a centre's list.
    class UnplacedAreaError < Error; end

    def self.find_or_create!(area:, nominal_code:, financial_year: nil, cost_centre: nil,
                             store: Reimbursements.build_store)
      # PERSISTED, not merely present: an unsaved Area has a nil id, and
      # `where(area_id: nil)` matches every arealess line in the portal — so an
      # unsaved "Cogito" was answered with the Contingency overhead.
      raise ArgumentError, "a saved area is required to identify a budget line" unless area&.persisted?

      code = nominal_code.to_s.strip
      # Not merely invalid: a blank code matches every uncoded line in the area.
      raise ArgumentError, "a nominal code is required to identify a budget line" if code.blank?

      # The area is the parent, so its own coordinates win over the caller's: a
      # line filed into a year or centre other than its area's splits the show
      # across two pots.
      centre = area.cost_centre || cost_centre
      lines = Budget.where(area_id: area.id).to_a

      # By code first, and without consulting the centre's list: a stored line
      # answers for a code the list has since lost, and refusing a READ costs a
      # producer a claim they could have filed.
      coded = by_code(lines, area: area, nominal_code: code)
      return coded if coded

      listed = listed_code(area, centre, code)
      # The same match the store re-takes under the lock, now that the label a
      # name match needs can be resolved.
      found = match(lines, area: area, nominal_code: code, label: listed.label)
      return found if found

      raise RetiredCodeError, retired_message(listed) unless listed.active

      store.find_or_create_budget_for_area!(
        area_id: area.id, nominal_code: listed.code, name: listed.label,
        cost_centre: centre, financial_year: area.financial_year || financial_year
      )
    end

    # The one matching rule, run twice per create: once on a read that can go
    # stale, and again inside the store's transaction under the area's row
    # lock. Two derivations of "which line is this" drift, which is Phase 2a's
    # whole lesson, so there is one — and it is PUBLIC solely so
    # DatabaseStore#find_or_create_budget_for_area! can re-take it under that
    # lock, not because anything else should call it.
    #
    # +nominal_code+ is the stored string and +label+ the name a line created
    # for that code would carry.
    def self.match(lines, area:, nominal_code:, label:)
      by_code(lines, area: area, nominal_code: nominal_code) ||
        by_label(lines, area: area, nominal_code: nominal_code, label: label)
    end

    # The line already booked to this code. Names are irrelevant here: the code
    # plus the area is the key, however the committee spelled the line.
    def self.by_code(lines, area:, nominal_code:)
      candidates = lines.select { |line| key(line.nominal_code) == key(nominal_code) }
      raise AmbiguousError, ambiguity(candidates, area, "nominal code #{nominal_code.inspect}") if candidates.many?

      candidates.first
    end
    private_class_method :by_code

    # The hand-named sibling this finder's own key cannot see. BudgetImport's
    # rule, so both spellings answer to one comparison: bare_name strips the
    # "Cogito: " prefix exactly where it is this line's own area's name, which
    # is how a line stored bare and a line stored prefixed are the same line.
    def self.by_label(lines, area:, nominal_code:, label:)
      candidates = lines.select { |line| key(BudgetImport.bare_name(line.name, area.name)) == key(label) }
      raise AmbiguousError, ambiguity(candidates, area, label.inspect) if candidates.many?

      line = candidates.first
      return nil if line.nil?
      return line if line.nominal_code.blank?

      # by_code already returned an equally-coded line, so this one's code
      # disagrees: the same name on another account. Re-pointing it books the
      # claim to a code nobody asked for, and a second line beside it is the
      # duplicate the area exists to prevent — neither is this finder's to
      # choose between.
      raise AmbiguousError, mismatch(line, area, nominal_code)
    end
    private_class_method :by_label

    def self.listed_code(area, cost_centre, code)
      raise UnplacedAreaError, unplaced_message(area) if cost_centre.nil?

      listed = NominalCode.find_by(cost_centre: cost_centre, code: code)
      return listed if listed

      raise UnknownCodeError,
            "#{code.inspect} is not on #{cost_centre.name}'s list of nominal codes, so there is " \
            "no label to name a budget line with. Add it on that cost centre's settings page first."
    end
    private_class_method :listed_code

    # Compared as BudgetImport compares a committee's spelling of a name, which
    # is also how the utf8mb4_unicode_ci columns behind both compare their own.
    def self.key(value) = BudgetImport.match_key(value)
    private_class_method :key

    def self.ambiguity(candidates, area, subject)
      "#{subject} matches more than one budget line in #{area.name} " \
        "(#{BudgetImport.budget_labels(candidates).to_sentence(last_word_connector: " and ")}). " \
        "Merge or rename them, so it is clear which line this spend belongs to."
    end
    private_class_method :ambiguity

    def self.mismatch(line, area, nominal_code)
      "#{line.name.inspect} in #{area.name} is already booked to nominal code " \
        "#{line.nominal_code.inspect}, not #{nominal_code.inspect}. Recode that line or rename " \
        "it, so it is clear which account this spend belongs to."
    end
    private_class_method :mismatch

    def self.unplaced_message(area)
      "#{area.name} is not in a cost centre yet, so there is no list of nominal codes to name a " \
        "budget line from. Put the area in its cost centre first."
    end
    private_class_method :unplaced_message

    def self.retired_message(listed)
      "Nominal code #{listed.code.inspect} (#{listed.label}) has been retired, so no new budget " \
        "line can be opened on it. Pick a current code, or bring that one back on the cost " \
        "centre's settings page."
    end
    private_class_method :retired_message
  end
end
