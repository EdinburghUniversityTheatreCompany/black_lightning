module Reimbursements
  ##
  # The budget line for one (area, nominal code), found where it exists and created where it
  # does not. A show's Marketing and Other lines carry the SAME code, so the area is what
  # qualifies it.
  #
  # The lookup is a read the store has no reader for; the WRITE goes through
  # DatabaseStore#find_or_create_budget_for_area!, which re-takes the same match under the
  # area's row lock.
  #
  # A line created in an area inherits the AREA's owners, so one created in an ownerless area
  # has no sign-off gate and its claims reach finance unendorsed.
  module BudgetFinder
    class Error < StandardError; end

    # Never a pick: a wrong one splits a show's spend across two lines or books it to another show.
    class AmbiguousError < Error; end

    # No label to name a new line with, and a line named after bare digits is one nobody chose.
    class UnknownCodeError < Error; end

    # Retired codes still label historical rows and still FIND their line, but take no new spend.
    class RetiredCodeError < Error; end

    # The area is in no cost centre yet, so there is no chart of accounts to read a label from.
    # The fix is placing the area, not adding a code.
    class UnplacedAreaError < Error; end

    def self.find_or_create!(area:, nominal_code:, financial_year: nil, cost_centre: nil,
                             store: Reimbursements.build_store)
      # PERSISTED, not merely present: an unsaved Area has a nil id, and `where(area_id: nil)`
      # matches every arealess line in the portal.
      raise ArgumentError, "a saved area is required to identify a budget line" unless area&.persisted?

      code = nominal_code.to_s.strip
      # A blank code matches every uncoded line in the area.
      raise ArgumentError, "a nominal code is required to identify a budget line" if code.blank?

      # The area's own coordinates win: a line filed into another year or centre splits the show
      # across two pots.
      centre = area.cost_centre || cost_centre
      lines = Budget.where(area_id: area.id).to_a

      # By code first, without consulting the centre's list: a stored line answers for a code
      # the list has since lost, and refusing a READ costs a producer a claim they could file.
      coded = by_code(lines, area: area, nominal_code: code)
      return coded if coded

      listed = listed_code(area, centre, code)
      found = match(lines, area: area, nominal_code: code, label: listed.label)
      return found if found

      raise RetiredCodeError, retired_message(listed) unless listed.active

      store.find_or_create_budget_for_area!(
        area_id: area.id, nominal_code: listed.code, name: listed.label,
        cost_centre: centre, financial_year: area.financial_year || financial_year
      )
    end

    # The one matching rule, run on a read that can go stale and again under the store's row
    # lock. Public only so DatabaseStore#find_or_create_budget_for_area! can re-take it.
    # +label+ is the name a line created for this code would carry.
    def self.match(lines, area:, nominal_code:, label:)
      by_code(lines, area: area, nominal_code: nominal_code) ||
        by_label(lines, area: area, nominal_code: nominal_code, label: label)
    end

    # Names are irrelevant here: code plus area is the key, however the committee spelled it.
    def self.by_code(lines, area:, nominal_code:)
      candidates = lines.select { |line| key(line.nominal_code) == key(nominal_code) }
      raise AmbiguousError, ambiguity(candidates, area, "nominal code #{nominal_code.inspect}") if candidates.many?

      candidates.first
    end
    private_class_method :by_code

    # The hand-named sibling by_code cannot see. Uses BudgetImport.bare_name, so a line stored
    # bare and one stored with the "Cogito: " prefix are the same line.
    def self.by_label(lines, area:, nominal_code:, label:)
      candidates = lines.select { |line| key(BudgetImport.bare_name(line.name, area.name)) == key(label) }
      raise AmbiguousError, ambiguity(candidates, area, label.inspect) if candidates.many?

      line = candidates.first
      return nil if line.nil?
      return line if line.nominal_code.blank?

      # The same name on another account. Re-pointing it books the claim to a code nobody asked
      # for, and a second line is the duplicate the area exists to prevent.
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

    # Compared as BudgetImport compares names, as do the utf8mb4_unicode_ci columns behind both.
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
