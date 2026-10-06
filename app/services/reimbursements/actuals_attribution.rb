module Reimbursements
  ##
  # Decides which cost centre each pasted EUSA actuals row belongs to, from the row's own Cost
  # Centre column, so one paste may span several centres. Lives apart from the pure Reconciliation
  # parser because it looks codes up in the database. Only the first outcome imports:
  #
  #   attributed        the row's code names a configured cost centre
  #   unrecognised_rows a code we don't have (another society's spend). Skipped, but reported with
  #                     its code in the preview: a silent drop is what this class exists to prevent.
  #   blank-code rows   no code in the export. These ALWAYS need an operator choice, even with one
  #                     centre configured: inferring the only one files real spend under the wrong
  #                     pot the day a second appears. Unchosen they sit in +unassigned_blank_rows+
  #                     and must not import.
  class ActualsAttribution
    # The blank-row choice meaning "these are not ours": a real answer, so the operator can get past
    # the mandatory question without parking the rows under the nearest centre.
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

      # For the "cost centres G12, H03 are not set up here" line.
      def unrecognised_codes
        unrecognised_rows.map { |row| row.cost_centre.to_s.strip.upcase }.uniq.sort
      end

      # Applying now would silently drop the blank-code rows.
      def blank_choice_required? = unassigned_blank_rows.any?

      # Every row this paste will NOT import, whatever the reason.
      def dropped_rows = unrecognised_rows + unassigned_blank_rows + skipped_blank_rows
    end

    def initialize(cost_centres:)
      @cost_centres = cost_centres.to_a
      @by_code = @cost_centres.index_by { |centre| normalise(centre.eusa_code) }
    end

    # +blank_choice+ is a cost centre id, SKIP or nothing. An unknown id reads as nothing, the safe
    # direction: the rows stay unimported and the question stays on screen.
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
