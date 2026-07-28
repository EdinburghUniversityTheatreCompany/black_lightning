module Reimbursements
  ##
  # Decides which cost centre each pasted EUSA actuals row belongs to.
  #
  # The export carries a Cost Centre column per row, so nobody has to tell the
  # wizard which centre a paste is for: every row lands in the centre its own
  # code names, and a paste may span as many centres as it likes. Filtering a
  # paste down to one code (a hardcoded "F40", or CostCentre.default) silently
  # drops every other society's row.
  #
  # This lives on the Rails side, apart from the pure Reconciliation parser,
  # precisely because deciding needs to look codes up in the database.
  #
  # Three outcomes, and only the first one imports:
  #
  #   attributed             the row's code names a configured cost centre
  #   unrecognised_rows      the row names a code we don't have (another
  #                          society's spend in a whole-organisation export).
  #                          Skipped — but VISIBLY: the preview reports the count
  #                          and the codes, because a silent drop is what this
  #                          class exists to prevent.
  #   blank-code rows        the export omitted the column, or left the cell
  #                          empty. These ALWAYS need an explicit operator
  #                          choice, even when only one cost centre is
  #                          configured: inferring "well, it must be the only
  #                          one" is exactly the guess that files real spend
  #                          under the wrong pot the day a second pot appears.
  #                          Unchosen, they sit in +unassigned_blank_rows+ and
  #                          must not import. The choice may also be SKIP, the
  #                          operator saying "these are not ours".
  class ActualsAttribution
    # The blank-row choice meaning "don't import these at all". A real choice,
    # so the operator can proceed past a mandatory question honestly rather than
    # parking the rows under whichever centre is nearest to hand.
    SKIP = "skip".freeze

    # One row and the cost centre it was attributed to.
    Attributed = Data.define(:row, :cost_centre)

    Result = Data.define(:attributed, :unrecognised_rows, :unassigned_blank_rows,
                         :skipped_blank_rows) do
      # The rows that may be imported, in paste order.
      def rows = attributed.map(&:row)

      # Identity strings parallel to #rows, for
      # Reconciliation.detect_offsetting_pairs' cost-centre gate. Ids rather
      # than codes, so blank-code rows the operator assigned by hand are gated
      # as members of the pot they chose rather than as "blank".
      def cost_centre_keys = attributed.map { |entry| entry.cost_centre.id.to_s }

      # The unrecognised codes as the operator typed them, de-duplicated, for
      # the "cost centres G12, H03 are not set up here" line.
      def unrecognised_codes
        unrecognised_rows.map { |row| row.cost_centre.to_s.strip.upcase }.uniq.sort
      end

      # Blank-code rows are still waiting on a choice, so nothing may be applied
      # yet: applying would silently drop them.
      def blank_choice_required? = unassigned_blank_rows.any?

      # Every row this paste will NOT import, whatever the reason.
      def dropped_rows = unrecognised_rows + unassigned_blank_rows + skipped_blank_rows
    end

    def initialize(cost_centres:)
      @cost_centres = cost_centres.to_a
      @by_code = @cost_centres.index_by { |centre| normalise(centre.eusa_code) }
    end

    # +blank_choice+ is what the operator picked for the blank-code rows: a cost
    # centre id, SKIP, or nothing. An id that matches no configured centre reads
    # as nothing — the safe direction, since it leaves those rows unimported and
    # the question still on screen.
    def call(rows, blank_choice: nil)
      chosen = resolve_blank_choice(blank_choice)
      attributed = []
      unrecognised = []
      unassigned_blank = []
      skipped_blank = []

      rows.each do |row|
        code = normalise(row.cost_centre)
        if code.empty?
          case chosen
          when nil then unassigned_blank << row
          when SKIP then skipped_blank << row
          else attributed << Attributed.new(row: row, cost_centre: chosen)
          end
        elsif (centre = @by_code[code])
          attributed << Attributed.new(row: row, cost_centre: centre)
        else
          unrecognised << row
        end
      end

      Result.new(attributed: attributed, unrecognised_rows: unrecognised,
                 unassigned_blank_rows: unassigned_blank, skipped_blank_rows: skipped_blank)
    end

    private

    def resolve_blank_choice(value)
      value = value.to_s.strip
      return nil if value.empty?
      return SKIP if value == SKIP

      @cost_centres.find { |centre| centre.id.to_s == value }
    end

    def normalise(value) = value.to_s.strip.upcase
  end
end
