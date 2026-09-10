module Reimbursements
  ##
  # Finance's spreadsheet of claims that were settled outside the portal, read
  # into buckets an operator confirms before anything is written. Table-less; a
  # pure function of its inputs, so the preview and the apply that follows it
  # can each build one from the same text and be certain they agree.
  #
  # Pasted TSV and uploaded xlsx both come in through ImportParsing, as
  # BudgetImport does, and an upload is normalised straight to TSV (#to_tsv)
  # and carried through the preview in a hidden field. Nothing is kept in the
  # session or on disk, and apply re-parses and re-validates from scratch.
  #
  # Buckets: +create+, +already_imported+ (a Reference already on record,
  # reported and never re-created) and +invalid+, which blocks the WHOLE import
  # — all-or-nothing like import_budgets!, because a half-imported ledger has no
  # audit value and re-running after a fix is cheap.
  #
  # No Person is ever created from a bare email (BudgetImport#resolve_owners
  # states the rule); the error points the operator at the People screen.
  #
  # **Double apply** is stopped by the sheet's own Reference, written to
  # `expenses.import_key` behind a UNIQUE index. The wizard is stateless so a
  # second click re-posts the same sheet, and a claim has no natural key the way
  # a budget line has its name. The pre-flight read below keeps the preview
  # honest; the index is what holds when that read goes stale.
  #
  # **Every rule comes from ExpenseForm**, because the Expense model validates
  # almost nothing — so each line goes through the same form the submission form
  # uses, with `internal` set as ExpenseForm.from_actual sets it.
  #
  # **Columns are matched here, NOT through ImportParsing#find_column**, whose
  # "any header containing the keyword" fallback is catastrophic on a sheet
  # whose fields are near-anagrams: read through it, "Payment reference"
  # answered to the dedupe key (collapsing two of a payee's claims into one) and
  # "Account number" answered to the expense number (numbering every later claim
  # in the portal from 66,374,959). Neither is catchable downstream. So: EXACT
  # names first, then MULTI-WORD phrases only — a bare word is never a substring
  # hint — two fields resolving to one column is a blocking error, and the
  # preview STATES the column read for each field.
  class ExpenseImport
    include ImportParsing

    # What a row became, plus everything the preview needs to explain it.
    Entry = Struct.new(:row, :bucket, :person, :budget, :attrs, :error, keyword_init: true)

    # One entry per column, in the order #to_tsv writes them: +label+ is the
    # canonical heading, +exact+ matches a header WHOLE, +contains+ matches a
    # substring and is multi-word only (see the class note).
    #
    # A heading not listed here is simply not found, which reads as "the sheet
    # has no X column" for a required field and a blank for an optional one —
    # the safe direction, since a column read as the WRONG field is silent
    # while one not read at all is stated.
    FIELDS = {
      reference: {
        label: "Reference",
        exact: [ "reference", "ref", "id", "claim id", "claim ref", "claim reference",
                 "row id", "our ref", "our reference", "sheet ref", "reference id" ],
        contains: [ "claim reference", "our reference", "reference id", "sheet reference" ]
      },
      status: {
        label: "Status",
        exact: [ "status", "state" ],
        contains: [ "claim status", "expense status", "payment status" ]
      },
      payee_email: {
        label: "Payee email",
        exact: [ "payee email", "email", "e mail", "email address", "payee", "claimant" ],
        contains: [ "payee email", "payee e mail", "claimant email", "claimant e mail",
                    "submitter email", "submitter e mail" ]
      },
      budget: {
        label: "Budget",
        exact: [ "budget", "budget name", "budget line", "category" ],
        contains: [ "budget name", "budget line", "budget category" ]
      },
      amount: {
        label: "Amount",
        exact: [ "amount", "total", "gross", "gross amount", "total amount", "amount gross" ],
        contains: [ "gross amount", "total amount", "amount incl vat", "amount including vat" ]
      },
      amount_excl_vat: {
        label: "Amount excl VAT",
        exact: [ "amount excl vat", "excl vat", "ex vat", "net", "net amount", "amount net" ],
        contains: [ "excl vat", "excluding vat", "ex vat", "net amount", "amount net" ]
      },
      description: {
        label: "Description",
        exact: [ "description", "details", "narrative", "purpose", "what for" ],
        contains: [ "what for", "what it was for" ]
      },
      payment_reference: {
        label: "Payment reference",
        exact: [ "payment reference", "payment ref", "bacs reference", "bacs ref" ],
        contains: [ "payment reference", "payment ref", "bacs reference", "bacs ref" ]
      },
      expense_type: {
        label: "Type",
        exact: [ "type", "kind", "expense type", "claim type" ],
        contains: [ "expense type", "claim type" ]
      },
      auto_number: {
        label: "Expense number",
        exact: [ "expense number", "claim number", "expense no", "claim no", "number", "no" ],
        contains: [ "expense number", "claim number" ]
      },
      submitted_on: {
        label: "Date submitted",
        exact: [ "date submitted", "submitted", "date claimed", "claimed", "date" ],
        contains: [ "date submitted", "submitted on", "date claimed", "date of claim" ]
      },
      paid_on: {
        label: "Date paid",
        exact: [ "date paid", "paid", "payment date", "date of payment" ],
        contains: [ "date paid", "paid on", "payment date", "date of payment" ]
      },
      payee_name_override: {
        label: "Payee name",
        exact: [ "payee name", "pay to", "supplier", "supplier name" ],
        contains: [ "payee name", "supplier name", "pay to" ]
      },
      sort_code_override: {
        label: "Sort code",
        exact: [ "sort code", "sortcode" ],
        contains: [ "sort code" ]
      },
      account_number_override: {
        label: "Account number",
        exact: [ "account number", "account no", "account" ],
        contains: [ "account number", "account no", "bank account" ]
      }
    }.freeze

    TSV_HEADERS = FIELDS.each_value.map { |spec| spec[:label] }.freeze

    # The only columns a sheet must carry. The rest are optional, and several
    # (Type, the payee trio) exist so a claim that needs them is importable at
    # all rather than because a typical sheet carries them.
    REQUIRED_FIELDS = %i[reference status payee_email budget amount].freeze

    # Fields whose cells may hold a tab or a newline, so must be unescaped when
    # the text came back from #to_tsv. See @escaped below.
    TEXT_FIELDS = %i[reference budget description payment_reference payee_name_override].freeze

    # Statuses a row may name, matched case-insensitively so a sheet saying
    # "paid" lands where the operator plainly meant it to.
    STATUSES = Status.all

    # A claim at one of these has already been paid, or never will be — the
    # reading behind ExpenseForm#settled?. Stated as the SETTLED set rather than
    # the live one on purpose, the same way BankDetailsRetention states its
    # terminal set: a status this doesn't recognise counts as live, so a new one
    # inherits the stricter rule rather than the looser one.
    SETTLED_STATUSES = [ Status::SUBMITTED, Status::PAID, Status::REJECTED ].freeze

    # expenses.import_key is a string(255). Checked here so an over-long
    # reference is a row the operator can fix, rather than a ValueTooLong
    # raised mid-transaction — which surfaces inside the wizard's Turbo Frame
    # as a 500 with the paste lost.
    IMPORT_KEY_LIMIT = 255

    # The required columns by their canonical heading, for the form's copy.
    def self.required_labels
      REQUIRED_FIELDS.map { |field| FIELDS.fetch(field)[:label] }
    end

    attr_reader :entries, :financial_year, :cost_centre

    # +input_type+ is :paste (the operator's own text), :xlsx (an upload), or
    # :canonical_tsv — this class's own #to_tsv output coming back from the
    # preview's hidden field, which is the ONLY input whose cells carry escape
    # sequences. Unescaping the operator's paste instead rewrote a typed
    # "C:\temp\report.pdf" with a real tab before storing it.
    def initialize(data, input_type:, financial_year:, cost_centre:, budgets: [], people: [],
                   existing_expenses: [])
      @errors = []
      @financial_year = financial_year
      @cost_centre = cost_centre
      @escaped = input_type == :canonical_tsv
      @budgets_by_name = budgets.index_by { |budget| BudgetImport.match_key(budget.name) }
      @people_by_email = people.index_by { |person| person.email.to_s.strip.downcase }
      @imported_keys = existing_expenses.filter_map { |e| self.class.key_match(e.import_key) }.to_set
      @taken_numbers = existing_expenses.filter_map(&:auto_number).to_set
      @rows = parse_data(data, @escaped ? :paste : input_type)
      @entries = categorize
    end

    # Compared the way the UNIQUE index does: import_key is utf8mb4_unicode_ci,
    # so "OLD-1" and "old-1" are ONE key to MySQL. Comparing case-sensitively
    # previewed them as two creates and then rolled the whole sheet back
    # forever, blaming a concurrent operator that did not exist.
    #
    # The collation also folds ACCENTS and this deliberately does not: a sheet
    # mixing "réf-1" and "ref-1" still dead-ends (#apply's rescue names the fix),
    # because over-matching would bucket a genuinely new claim as already
    # imported and drop it silently — the far worse direction.
    def self.key_match(value) = value.to_s.strip.downcase.presence

    # Nothing is written unless every row is readable. See the class comment.
    def valid?
      @errors.empty? && @entries.any? && @entries.none? { |entry| entry.bucket == :invalid }
    end

    def entries_in(bucket) = @entries.select { |entry| entry.bucket == bucket }

    # Attributes for each new claim, ready for DatabaseStore#import_expenses!.
    def creates
      entries_in(:create).map(&:attrs)
    end

    # Claims about to be created at a status the portal still acts on. The
    # preview says out loud what will happen to them: an Approved claim goes on
    # the next BACS spreadsheet for its cost centre — EUSA pays it a second
    # time — and its producer is emailed; a Pending or Draft one lands in Review
    # and is named to its budget owners on the next nightly run-day. That is a
    # legitimate thing to want (finance may be importing a live queue), but it
    # is the opposite of the "bookkeeping only" the rest of this screen implies.
    def live_entries
      entries_in(:create).reject { |entry| SETTLED_STATUSES.include?(entry.row[:status]) }
    end

    # Canonical heading => the sheet's own heading it was read from (nil when
    # the sheet has no such column). Rendered by the preview: keyword matching
    # can only ever be nearly right, and stating what was read is worth more
    # than any amount of tuning.
    def column_mapping
      FIELDS.to_h { |field, spec| [ spec[:label], header_for[field] ] }
    end

    # The sheet as canonical TSV, for the hidden field that carries an upload
    # from the preview into apply. Tabs and newlines inside a cell are escaped
    # rather than dropped: an xlsx cell really can contain them, and one stray
    # tab would otherwise shift every later column when apply re-parses.
    def to_tsv
      ([ TSV_HEADERS.join("\t") ] + @rows.map { |row| tsv_row(row) }).join("\n")
    end

    private

    def header_for
      @header_for ||= {}
    end

    def tsv_row(row)
      FIELDS.each_key.map { |field| escape_cell(cell_for(row, field)) }.join("\t")
    end

    # An unreadable value is carried on VERBATIM. The preview re-renders from
    # this text after a blocked apply, so replacing it with a blank would hide
    # the very cell the operator has to go and fix.
    def cell_for(row, field)
      value = row[field]
      case value
      when nil then ""
      when :unreadable then row[:"raw_#{field}"].to_s
      when BigDecimal then value.to_s("F")
      when Date then value.iso8601
      else value.to_s
      end
    end

    # One normalised row per sheet line. Called by ImportParsing's parsers.
    # Returns nil for a wholly blank line so trailing sheet padding is ignored
    # rather than reported as thirty nameless claims.
    def normalize_row(raw)
      @header_for ||= resolve_headers(raw.keys)
      return nil if raw.values.all?(&:blank?)

      row = FIELDS.each_key.to_h { |field| [ field, text(raw, field) ] }
      %i[amount amount_excl_vat].each { |field| read_amount(row, field) }
      %i[submitted_on paid_on].each { |field| read_date(row, field) }
      row[:payee_email] = row[:payee_email].downcase
      row[:status] = normalize_status(row[:status])
      row[:expense_type] = normalize_type(row[:expense_type])
      row
    end

    # Escape sequences are undone only for text that came back from #to_tsv —
    # never for the operator's own paste, where a backslash is a backslash.
    def text(raw, field)
      value = raw[header_for[field]].to_s.strip
      @escaped && TEXT_FIELDS.include?(field) ? unescape_cell(value) : value
    end

    def read_amount(row, field)
      raw = row[field]
      row[field] = parse_amount(raw)
      row[:"raw_#{field}"] = raw if row[field] == :unreadable
    end

    def read_date(row, field)
      raw = row[field]
      row[field] = parse_date(raw)
      row[:"raw_#{field}"] = raw if row[field] == :unreadable
    end

    # --- Which column is which -----------------------------------------------

    def resolve_headers(headers)
      FIELDS.transform_values { |spec| match_header(headers, spec) }
    end

    # Punctuation and case carry no meaning in a spreadsheet heading, so
    # "E-mail", "e mail" and "EMAIL" are one name. Every FIELDS entry is
    # written in this normalised form already.
    def normalize_header(value)
      value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def match_header(headers, spec)
      spec[:exact].each do |name|
        found = headers.find { |header| normalize_header(header) == name }
        return found if found
      end
      spec[:contains].each do |phrase|
        found = headers.find { |header| normalize_header(header).include?(phrase) }
        return found if found
      end
      nil
    end

    # Two fields reading the same column is refused rather than resolved: which
    # of them the operator meant is exactly what cannot be guessed, and picking
    # one writes the wrong value into a money or identity field with nothing on
    # screen to say so.
    def ambiguous_columns
      header_for.compact.group_by { |_field, header| header }
                .select { |_header, pairs| pairs.size > 1 }
    end

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
      return nil if raw.blank?

      STATUSES.find { |status| status.casecmp?(raw) } || raw
    end

    def normalize_type(raw)
      return Expense::TYPE_REIMBURSEMENT if raw.blank?

      Expense::TYPES.find { |type| type.casecmp?(raw) } || raw
    end

    # --- Categorisation ------------------------------------------------------

    def categorize
      return [] if @rows.empty?

      # A problem with the SHEET is one problem, not thirty broken lines.
      report_ambiguous_columns
      report_missing_columns
      return [] if @errors.any?

      duplicated = duplicated_values
      @rows.map { |row| entry_for(row, duplicated) }
    end

    def report_ambiguous_columns
      ambiguous_columns.each do |header, pairs|
        labels = pairs.map { |field, _| FIELDS.fetch(field)[:label] }
        @errors << "The column #{header.inspect} would be read as both " \
                   "#{labels.to_sentence(last_word_connector: ' and ')}. Rename one of them, " \
                   "or start from the template."
      end
    end

    def report_missing_columns
      missing = REQUIRED_FIELDS.reject { |field| header_for[field] }
                               .map { |field| FIELDS.fetch(field)[:label] }
      return if missing.empty?

      @errors << "The sheet has no #{missing.to_sentence} column#{'s' if missing.many?}. " \
                 "Every claim needs #{missing.many? ? 'those' : 'that'} — start from the " \
                 "template if you're not sure of the headings."
    end

    def entry_for(row, duplicated)
      person = @people_by_email[row[:payee_email]]
      budget = @budgets_by_name[BudgetImport.match_key(row[:budget])]
      base = { row: row, person: person, budget: budget }

      error = row_error(row, person, budget, duplicated)
      return Entry.new(**base, bucket: :invalid, error: error) if error

      if @imported_keys.include?(self.class.key_match(row[:reference]))
        return Entry.new(**base, bucket: :already_imported)
      end

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
      reference_error(row, duplicated) ||
        status_error(row) ||
        (payee_error(row) if person.nil?) ||
        (budget_error(row) if budget.nil?) ||
        value_error(row) ||
        auto_number_error(row, duplicated)
    end

    def reference_error(row, duplicated)
      if row[:reference].blank?
        "This line has no reference. Give every claim one (its row number in your own sheet " \
          "will do) — it's what stops a second import creating the same claim twice."
      elsif row[:reference].length > IMPORT_KEY_LIMIT
        "That reference is too long: #{row[:reference].length} characters, and the limit is " \
          "#{IMPORT_KEY_LIMIT}."
      elsif duplicated[:references].include?(self.class.key_match(row[:reference]))
        "#{row[:reference].inspect} is used by more than one line in this sheet, so a re-import " \
          "couldn't tell them apart. (References are matched ignoring case.)"
      end
    end

    def status_error(row)
      if row[:status].blank?
        "This line has no status. Say what state the claim is in: " \
          "#{STATUSES.to_sentence(last_word_connector: ' or ')}."
      elsif STATUSES.exclude?(row[:status])
        "#{row[:status].inspect} isn't a status. Use " \
          "#{STATUSES.to_sentence(last_word_connector: ' or ')}."
      end
    end

    def value_error(row)
      if row[:amount] == :unreadable
        "#{row[:raw_amount].inspect} isn't an amount."
      elsif row[:amount_excl_vat] == :unreadable
        "#{row[:raw_amount_excl_vat].inspect} isn't an amount. Leave it blank to charge the " \
          "whole amount to the budget."
      elsif row[:submitted_on] == :unreadable
        "#{row[:raw_submitted_on].inspect} isn't a date. Use 2026-05-13 or 13/05/2026."
      elsif row[:paid_on] == :unreadable
        "#{row[:raw_paid_on].inspect} isn't a date. Use 2026-05-13 or 13/05/2026."
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
      references = @rows.filter_map { |row| self.class.key_match(row[:reference]) }
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
