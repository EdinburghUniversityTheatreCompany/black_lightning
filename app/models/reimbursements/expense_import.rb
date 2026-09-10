module Reimbursements
  ##
  # Finance's spreadsheet of claims that were settled outside the portal, read
  # into buckets an operator confirms before anything is written. Table-less; a
  # pure function of its inputs, so the preview and the apply that follows it
  # can each build one from the same text and be certain they agree.
  #
  # Pasted TSV and uploaded xlsx both come in through ImportParsing, exactly as
  # BudgetImport does, and an upload is normalised straight to TSV (#to_tsv)
  # and carried through the preview in a hidden field. Nothing is kept in the
  # session or on disk, and apply re-parses and re-validates from scratch.
  #
  # THE BUCKETS:
  #
  #   create           a claim this portal has never seen
  #   already_imported a reference already on record — reported, never re-created
  #   invalid          unreadable; blocks the WHOLE import
  #
  # ALL-OR-NOTHING, like import_budgets! and unlike Reconcile's per-row rescue:
  # an unreadable amount, an unknown payee, an unknown budget or a bad status
  # stops everything and names the offending rows. A half-imported ledger has no
  # audit value, and re-running after a fix is cheap because the Reference
  # column makes the whole sheet idempotent.
  #
  # NO Person is ever created from a bare email — the rule BudgetImport's
  # #resolve_owners states. The operator registers the payee on the People
  # screen, which the error points them at.
  #
  # WHAT STOPS A DOUBLE APPLY. The wizard is stateless, so a second click
  # re-posts the same sheet; a claim has no natural key the way a budget line
  # has its name, so the sheet carries one. Every row's Reference is written to
  # expenses.import_key, which has a UNIQUE index — the pre-flight read below
  # keeps the preview honest, and the index is what actually holds when that
  # read goes stale (a double submit, or two operators).
  #
  # EVERY RULE COMES FROM ExpenseForm. The Expense model validates almost
  # nothing (person, budget, batch and financial year are all optional; status,
  # type and payment method have DB defaults), so an importer that wrote rows
  # directly would enforce nothing at all. Each line is validated through the
  # same form object the submission form uses, with `internal` set as
  # ExpenseForm.from_actual sets it — a claim imported here has no receipt, no
  # itemised VAT and nobody to tick a soft block's acknowledgement.
  class ExpenseImport
    include ImportParsing

    # What a row became, plus everything the preview needs to explain it.
    Entry = Struct.new(:row, :bucket, :person, :budget, :attrs, :error, keyword_init: true)

    # Canonical headers — what #to_tsv writes and what the downloadable template
    # carries. Reading is more forgiving than this (see the COLUMNS keywords).
    TSV_HEADERS = [
      "Reference", "Status", "Payee email", "Budget", "Amount", "Amount excl VAT",
      "Description", "Payment reference", "Type", "Expense number", "Date submitted",
      "Date paid", "Payee name", "Sort code", "Account number"
    ].freeze

    # The only columns a sheet must carry, canonical heading to the field it
    # stands for. The rest are optional, and several (Type, the payee trio)
    # exist so a claim that needs them is importable at all rather than because
    # a typical sheet carries them. Keyed this way so a MISSING one can be
    # looked for under every keyword its field answers to, not just its
    # canonical spelling.
    REQUIRED_FIELDS = {
      "Reference" => :reference, "Status" => :status, "Payee email" => :payee_email,
      "Budget" => :budget, "Amount" => :amount
    }.freeze

    # Header keywords per field, most specific first, fed to ImportParsing's
    # #find_column (exact match, then "header contains all these words").
    #
    # Ordering matters wherever two headers share a word. "Amount excl VAT" is
    # listed before the bare "amount" so a sheet carrying both doesn't read the
    # same column twice; "Payment reference" comes before "Reference" for the
    # same reason, and the import key's own keywords deliberately exclude
    # "payment".
    COLUMNS = {
      reference: [ %w[reference\ id], %w[our\ ref], %w[claim\ ref], %w[row\ id], %w[reference] ],
      status: [ %w[status], %w[state] ],
      payee_email: [ %w[payee\ email], %w[claimant\ email], %w[submitter\ email], %w[email] ],
      budget: [ %w[budget\ name], %w[budget], %w[category] ],
      amount_excl_vat: [ %w[excl\ vat], %w[ex\ vat], %w[net\ amount], %w[net] ],
      amount: [ %w[gross\ amount], %w[total\ amount], %w[amount], %w[gross], %w[total] ],
      description: [ %w[description], %w[what\ for], %w[details], %w[narrative] ],
      payment_reference: [ %w[payment\ reference], %w[bacs\ reference], %w[payment\ ref] ],
      expense_type: [ %w[expense\ type], %w[type], %w[kind] ],
      auto_number: [ %w[expense\ number], %w[claim\ number], %w[number], %w[no] ],
      submitted_on: [ %w[date\ submitted], %w[submitted], %w[date\ claimed] ],
      paid_on: [ %w[date\ paid], %w[paid], %w[payment\ date] ],
      payee_name_override: [ %w[payee\ name], %w[pay\ to], %w[supplier] ],
      sort_code_override: [ %w[sort\ code], %w[sortcode] ],
      account_number_override: [ %w[account\ number], %w[account\ no], %w[account] ]
    }.freeze

    # Statuses a row may name, matched case-insensitively so a sheet saying
    # "paid" lands where the operator plainly meant it to.
    STATUSES = Status.all

    # A claim at one of these has already been paid, or never will be — the
    # reading behind ExpenseForm#settled?. Stated as the SETTLED set rather than
    # the live one on purpose, the same way BankDetailsRetention states its
    # terminal set: a status this doesn't recognise counts as live, so a new one
    # inherits the stricter rule rather than the looser one.
    SETTLED_STATUSES = [ Status::SUBMITTED, Status::PAID, Status::REJECTED ].freeze

    attr_reader :entries, :financial_year, :cost_centre

    def initialize(data, input_type:, financial_year:, cost_centre:, budgets: [], people: [],
                   existing_expenses: [])
      @errors = []
      @financial_year = financial_year
      @cost_centre = cost_centre
      @budgets_by_name = budgets.index_by { |budget| BudgetImport.match_key(budget.name) }
      @people_by_email = people.index_by { |person| person.email.to_s.strip.downcase }
      @imported_keys = existing_expenses.filter_map { |e| e.import_key.presence }.to_set
      @taken_numbers = existing_expenses.filter_map(&:auto_number).to_set
      @rows = parse_data(data, input_type)
      @entries = categorize
    end

    # Nothing is written unless every row is readable. See the class comment.
    def valid?
      @errors.empty? && @entries.any? && @entries.none? { |entry| entry.bucket == :invalid }
    end

    def entries_in(bucket) = @entries.select { |entry| entry.bucket == bucket }

    # Attributes for each new claim, ready for DatabaseStore#import_expenses!.
    def creates
      entries_in(:create).map(&:attrs)
    end

    # The sheet as canonical TSV, for the hidden field that carries an upload
    # from the preview into apply. Tabs and newlines inside a cell are escaped
    # rather than dropped: an xlsx cell really can contain them, and one stray
    # tab would otherwise shift every later column when apply re-parses.
    def to_tsv
      ([ TSV_HEADERS.join("\t") ] + @rows.map { |row| tsv_row(row) }).join("\n")
    end

    private

    def tsv_row(row)
      [ row[:reference], row[:status], row[:payee_email], row[:budget],
        amount_cell(row, :amount), amount_cell(row, :amount_excl_vat),
        row[:description], row[:payment_reference], row[:expense_type],
        row[:auto_number], date_cell(row, :submitted_on), date_cell(row, :paid_on),
        row[:payee_name_override], row[:sort_code_override], row[:account_number_override] ]
        .map { |value| escape_cell(value) }.join("\t")
    end

    # An unreadable value is carried on VERBATIM. The preview re-renders from
    # this text after a blocked apply, so replacing it with a blank would hide
    # the very cell the operator has to go and fix.
    def amount_cell(row, field)
      case row[field]
      when nil then ""
      when :unreadable then row[:"raw_#{field}"].to_s
      else row[field].to_s("F")
      end
    end

    def date_cell(row, field)
      case row[field]
      when nil then ""
      when :unreadable then row[:"raw_#{field}"].to_s
      else row[field].iso8601
      end
    end

    ESCAPES = { "\\" => "\\\\", "\t" => "\\t", "\n" => "\\n" }.freeze
    UNESCAPES = { "\\" => "\\", "t" => "\t", "n" => "\n" }.freeze

    # Block-form gsub throughout: the replacement-string form would read a
    # backslash in the replacement as a backreference.
    def escape_cell(value)
      value.to_s.delete("\r").gsub(/[\\\t\n]/) { |char| ESCAPES.fetch(char) }
    end

    def unescape_cell(value)
      value.to_s.gsub(/\\(.)/) { UNESCAPES.fetch(::Regexp.last_match(1), ::Regexp.last_match(0)) }
    end

    # One normalised row per sheet line. Called by ImportParsing's parsers.
    # Returns nil for a wholly blank line so trailing sheet padding is ignored
    # rather than reported as thirty nameless claims.
    def normalize_row(row)
      return nil if row.values.all?(&:blank?)

      @headers_seen ||= row.keys
      amount = parse_amount(column(row, :amount))
      excl_vat = parse_amount(column(row, :amount_excl_vat))
      submitted_on = parse_date(column(row, :submitted_on))
      paid_on = parse_date(column(row, :paid_on))
      {
        reference: unescape_cell(column(row, :reference)).strip,
        status: normalize_status(column(row, :status)),
        payee_email: column(row, :payee_email).to_s.strip.downcase,
        budget: unescape_cell(column(row, :budget)).strip,
        amount: amount,
        raw_amount: (column(row, :amount).to_s.strip if amount == :unreadable),
        amount_excl_vat: excl_vat,
        raw_amount_excl_vat: (column(row, :amount_excl_vat).to_s.strip if excl_vat == :unreadable),
        description: unescape_cell(column(row, :description)).strip,
        payment_reference: unescape_cell(column(row, :payment_reference)).strip,
        expense_type: normalize_type(column(row, :expense_type)),
        auto_number: column(row, :auto_number).to_s.strip,
        submitted_on: submitted_on,
        raw_submitted_on: (column(row, :submitted_on).to_s.strip if submitted_on == :unreadable),
        paid_on: paid_on,
        raw_paid_on: (column(row, :paid_on).to_s.strip if paid_on == :unreadable),
        payee_name_override: unescape_cell(column(row, :payee_name_override)).strip,
        sort_code_override: column(row, :sort_code_override).to_s.strip,
        account_number_override: column(row, :account_number_override).to_s.strip
      }
    end

    def column(row, field)
      COLUMNS.fetch(field).each do |keywords|
        value = find_column(row, *keywords)
        return value if value.present?
      end
      nil
    end

    # Blank stays blank; anything unreadable becomes the :unreadable marker so
    # the row can be flagged by name instead of silently importing as nil — the
    # distinction AmountParser.parse! exists to make.
    def parse_amount(raw)
      AmountParser.parse!(raw)
    rescue AmountParser::Error
      :unreadable
    end

    def parse_date(raw)
      value = raw.to_s.strip
      return nil if value.blank?

      Date.parse(value)
    rescue Date::Error
      :unreadable
    end

    # Nil rather than "" for a blank, so #row_error can tell "no status typed"
    # from "a status I don't recognise" and say the right thing about each.
    def normalize_status(raw)
      return nil if raw.to_s.strip.blank?

      STATUSES.find { |status| status.casecmp?(raw.to_s.strip) } || raw.to_s.strip
    end

    def normalize_type(raw)
      return Expense::TYPE_REIMBURSEMENT if raw.to_s.strip.blank?

      Expense::TYPES.find { |type| type.casecmp?(raw.to_s.strip) } || raw.to_s.strip
    end

    # --- Categorisation ------------------------------------------------------

    def categorize
      return [] if @rows.empty?

      # A column the whole sheet is missing is ONE problem with the sheet, not
      # thirty broken lines — judged on the HEADERS, so a sheet that does have a
      # Status column but left one cell empty gets that row flagged by itself.
      missing = REQUIRED_FIELDS.keys.reject { |header| header_present?(header) }
      if missing.any?
        @errors << "The sheet has no #{missing.to_sentence} column#{'s' if missing.many?}. " \
                   "Every claim needs #{missing.many? ? 'those' : 'that'} — start from the " \
                   "template if you're not sure of the headings."
        return []
      end

      duplicated = duplicated_values
      @rows.map { |row| entry_for(row, duplicated) }
    end

    # Whether the sheet carries a column for +header+ at all, judged on the
    # HEADERS and under every keyword that field answers to — so a sheet whose
    # status column is headed "State" counts as having one.
    def header_present?(header)
      COLUMNS.fetch(REQUIRED_FIELDS.fetch(header)).flatten.any? do |keyword|
        Array(@headers_seen).any? { |key| key.to_s.downcase.include?(keyword) }
      end
    end

    def entry_for(row, duplicated)
      person = @people_by_email[row[:payee_email]]
      budget = @budgets_by_name[BudgetImport.match_key(row[:budget])]
      base = { row: row, person: person, budget: budget }

      error = row_error(row, person, budget, duplicated)
      return Entry.new(**base, bucket: :invalid, error: error) if error

      return Entry.new(**base, bucket: :already_imported) if @imported_keys.include?(row[:reference])

      form = form_for(row, budget)
      unless form.valid?
        return Entry.new(**base, bucket: :invalid,
                         error: form.errors.full_messages.to_sentence)
      end

      Entry.new(**base, bucket: :create, attrs: attrs_for(row, form, person))
    end

    # Everything a row can be wrong about BEFORE the form sees it: the sheet's
    # own coordinates (reference, status) and the two records it has to resolve.
    # Ordered cheapest-and-most-fundamental first, so a row missing its
    # reference is told that rather than being told about its budget.
    def row_error(row, person, budget, duplicated)
      if row[:reference].blank?
        "This line has no reference. Give every claim one (its row number in your own sheet " \
          "will do) — it's what stops a second import creating the same claim twice."
      elsif duplicated[:references].include?(row[:reference])
        "#{row[:reference].inspect} is used by more than one line in this sheet, so a re-import " \
          "couldn't tell them apart."
      elsif row[:status].blank?
        "This line has no status. Say what state the claim is in: " \
          "#{STATUSES.to_sentence(last_word_connector: ' or ')}."
      elsif STATUSES.exclude?(row[:status])
        "#{row[:status].inspect} isn't a status. Use " \
          "#{STATUSES.to_sentence(last_word_connector: ' or ')}."
      elsif person.nil?
        payee_error(row)
      elsif budget.nil?
        budget_error(row)
      elsif row[:amount] == :unreadable
        "#{row[:raw_amount].inspect} isn't an amount."
      elsif row[:amount_excl_vat] == :unreadable
        "#{row[:raw_amount_excl_vat].inspect} isn't an amount. Leave it blank to charge the " \
          "whole amount to the budget."
      elsif row[:submitted_on] == :unreadable
        "#{row[:raw_submitted_on].inspect} isn't a date. Use 2026-05-13 or 13/05/2026."
      elsif row[:paid_on] == :unreadable
        "#{row[:raw_paid_on].inspect} isn't a date. Use 2026-05-13 or 13/05/2026."
      else
        auto_number_error(row, duplicated)
      end
    end

    # Never auto-created from a bare email — a person named by their address is
    # what the unique index on Person#email exists to stop, and a claim paid to
    # a stub record has nowhere to send the money. Points at the screen that
    # fixes it, as the budget import's preview does.
    def payee_error(row)
      if row[:payee_email].blank?
        "This line names no payee. Give the email address of the person the claim belongs to."
      else
        "#{row[:payee_email].inspect} isn't anyone on the People screen. Register them there " \
          "first — nobody is created from a bare email address."
      end
    end

    def budget_error(row)
      if row[:budget].blank?
        "This line names no budget, so there's nothing to charge it to."
      else
        "#{row[:budget].inspect} isn't a budget in #{destination_label}. Check the spelling, or " \
          "import the budget sheet first."
      end
    end

    # An explicit number is honoured, so a historical claim keeps the number it
    # was known by — but never blindly: auto_number is uniquely indexed, and
    # create_expense! deliberately does NOT retry past a collision on a number
    # it was handed, calling that real data corruption. So the collision is
    # caught here, where it can be reported by row instead of raising.
    def auto_number_error(row, duplicated)
      return nil if row[:auto_number].blank?

      number = Integer(row[:auto_number], 10)
      if duplicated[:numbers].include?(number)
        "Expense number #{number} is used by more than one line in this sheet."
      elsif @taken_numbers.include?(number)
        "Expense number #{number} already belongs to another claim in the portal."
      end
    rescue ArgumentError
      "#{row[:auto_number].inspect} isn't an expense number."
    end

    def duplicated_values
      references = @rows.map { |row| row[:reference] }.compact_blank
                        .tally.select { |_ref, count| count > 1 }.keys.to_set
      numbers = @rows.filter_map { |row| Integer(row[:auto_number], 10) rescue nil }
                     .tally.select { |_number, count| count > 1 }.keys.to_set
      { references: references, numbers: numbers }
    end

    def destination_label
      [ financial_year&.label, cost_centre&.name ].compact_blank.join(" / ").presence || "this year"
    end

    # The form object the submission and finance-edit screens use, so the
    # importer enforces the same rules rather than a restatement of them that
    # can drift. `internal` is set exactly as ExpenseForm.from_actual sets it:
    # an imported claim has no receipt to attach and no itemised VAT, and there
    # is nobody present to tick a soft block's acknowledgement.
    def form_for(row, budget)
      ExpenseForm.new(
        expense_type: row[:expense_type],
        internal: true,
        settled: SETTLED_STATUSES.include?(row[:status]),
        require_receipts: false,
        budget_record_id: budget.record_id,
        amount: row[:amount]&.to_s("F"),
        # Blank ex-VAT charges the WHOLE amount to the budget, the conservative
        # reading and the one ExpenseForm.from_actual already takes for a cost
        # with no VAT breakdown. Nil would fail its own presence rule and read
        # as a broken row.
        amount_excl_vat: (row[:amount_excl_vat] || row[:amount])&.to_s("F"),
        description: row[:description],
        payment_reference: row[:payment_reference],
        payee_name_override: row[:payee_name_override],
        sort_code_override: row[:sort_code_override],
        account_number_override: row[:account_number_override]
      )
    end

    # The form's own parsed attributes, plus the columns only an import writes.
    #
    # create_attrs is read rather than the row: AR casts a String to a decimal
    # column with #to_d, so handing a validated "£1,200" straight through would
    # store 0. The status is merged OVER the form's own (which is only ever
    # Draft or Pending), exactly as the actuals->expense conversion merges Paid.
    def attrs_for(row, form, person)
      attrs = form.create_attrs(person.record_id).merge(
        status: row[:status],
        import_key: row[:reference],
        financial_year: financial_year,
        payment_confirmed_date: row[:paid_on],
        submitted_at: row[:submitted_on]&.beginning_of_day
      )
      # Only present when the sheet gave one: create_expense! reads
      # `attrs.key?(:auto_number)` to decide whether a unique-index collision is
      # worth retrying, so a nil under that key would silently disable the retry
      # for every row.
      attrs[:auto_number] = Integer(row[:auto_number], 10) if row[:auto_number].present?
      attrs
    end
  end
end
