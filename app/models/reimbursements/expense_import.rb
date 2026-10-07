module Reimbursements
  ##
  # Finance's spreadsheet of claims settled outside the portal, read into buckets
  # (create, already_imported, invalid) an operator confirms before anything is
  # written. Table-less and a pure function of its inputs, so the preview and the
  # apply after it agree. One invalid row blocks the whole import.
  #
  # The sheet's ID is written to `expenses.import_key` behind a UNIQUE index: the
  # wizard is stateless, so a second click re-posts the same sheet, and a claim has
  # no natural key. Every other rule comes from ExpenseForm, with `internal` set as
  # ExpenseForm.from_actual sets it, because the Expense model validates almost nothing.
  #
  # Columns are matched here, NOT through ImportParsing#find_column. Its "header
  # contains the keyword" fallback read "Payment reference" as the dedupe key
  # (collapsing two of a payee's claims into one) and "Account number" as the expense
  # number (numbering every later claim in the portal from 66,374,959). So: exact names
  # first, then multi-word phrases only; two fields on one column is a blocking error;
  # the preview states the column read for each field.
  class ExpenseImport
    include ImportParsing
    include StrictColumnMatching

    # What a row became, plus everything the preview needs to explain it.
    Entry = Struct.new(:row, :bucket, :person, :budget, :attrs, :error, :unknown_submitter,
                       keyword_init: true)

    # One entry per column, in #to_tsv order: +label+ is the canonical heading, +hint+
    # the template's explanation row, +exact+ matches a header whole, +contains+ a
    # multi-word substring. A heading not listed is not found, which is stated; one
    # read as the wrong field would not be.
    FIELDS = {
      # Headed "ID", not "Reference": beside a Payment reference the two read as one
      # thing, and they are opposites (unique per claim vs repeated across a payee's claims).
      reference: {
        label: "ID",
        hint: "Your sheet's own id for this claim, different on every row",
        exact: [ "id", "reference", "ref", "claim id", "claim ref", "claim reference",
                 "row id", "our ref", "our reference", "sheet ref", "reference id" ],
        contains: [ "claim reference", "our reference", "reference id", "sheet reference" ]
      },
      status: {
        label: "Status",
        hint: "Paid, Submitted or Rejected for history; Approved, Pending or Draft go into the live queue",
        exact: [ "status", "state" ],
        contains: [ "claim status", "expense status", "payment status" ]
      },
      # "Submitter", not "Payee": on an Invoice the payee is the supplier, in Payee name.
      payee_email: {
        label: "Submitter email",
        hint: "Email of the person the claim belongs to, as on the People screen",
        exact: [ "submitter email", "payee email", "email", "e mail", "email address", "payee" ],
        contains: [ "submitter email", "submitter e mail", "payee email", "payee e mail",
                    "claimant email", "claimant e mail" ]
      },
      submitter_name: {
        label: "Submitter",
        hint: "Their name instead, if the email is blank",
        exact: [ "submitter", "submitter name", "claimant", "claimant name" ],
        contains: [ "submitter name", "claimant name" ]
      },
      budget: {
        label: "Budget",
        hint: "The budget line's name; write Area: Name if two lines share it",
        exact: [ "budget", "budget name", "budget line", "category" ],
        contains: [ "budget name", "budget line", "budget category" ]
      },
      amount: {
        label: "Amount",
        hint: "Total paid in pounds, including VAT",
        exact: [ "amount", "total", "gross", "gross amount", "total amount", "amount gross" ],
        contains: [ "gross amount", "total amount", "amount incl vat", "amount including vat" ]
      },
      amount_excl_vat: {
        label: "Amount excl VAT",
        hint: "Optional; blank charges the whole amount to the budget",
        exact: [ "amount excl vat", "excl vat", "ex vat", "net", "net amount", "amount net" ],
        contains: [ "excl vat", "excluding vat", "ex vat", "net amount", "amount net" ]
      },
      description: {
        label: "Description",
        hint: "Required; what it was for",
        exact: [ "description", "details", "narrative", "purpose", "what for" ],
        contains: [ "what for", "what it was for" ]
      },
      payment_reference: {
        label: "Payment reference",
        hint: "Required; the reference on the bank transfer, which may repeat across " \
              "one person's claims. Any short label will do on a historical claim",
        exact: [ "payment reference", "payment ref", "bacs reference", "bacs ref" ],
        contains: [ "payment reference", "payment ref", "bacs reference", "bacs ref" ]
      },
      expense_type: {
        label: "Type",
        hint: "Reimbursement (blank) if the payee was paid back, Invoice if EUSA paid a " \
              "supplier, From EUSA for a cost EUSA charged directly",
        exact: [ "type", "kind", "expense type", "claim type" ],
        contains: [ "expense type", "claim type" ]
      },
      auto_number: {
        label: "Expense number",
        hint: "Optional; the claim's old number, or blank to number it automatically",
        exact: [ "expense number", "claim number", "expense no", "claim no", "number", "no" ],
        contains: [ "expense number", "claim number" ]
      },
      submitted_on: {
        label: "Date submitted",
        hint: "Optional; 2026-05-13 or 13/05/2026",
        exact: [ "date submitted", "submitted", "date claimed", "claimed", "date" ],
        contains: [ "date submitted", "submitted on", "date claimed", "date of claim" ]
      },
      paid_on: {
        label: "Date paid",
        hint: "Optional; 2026-05-13 or 13/05/2026",
        exact: [ "date paid", "paid", "payment date", "date of payment" ],
        contains: [ "date paid", "paid on", "payment date", "date of payment" ]
      },
      payee_name_override: {
        label: "Payee name",
        hint: "Invoices only: the supplier's name",
        exact: [ "payee name", "pay to", "supplier", "supplier name" ],
        contains: [ "payee name", "supplier name", "pay to" ]
      },
      sort_code_override: {
        label: "Sort code",
        hint: "Invoices only: the supplier's sort code",
        exact: [ "sort code", "sortcode" ],
        contains: [ "sort code" ]
      },
      account_number_override: {
        label: "Account number",
        hint: "Invoices only: the supplier's account number",
        exact: [ "account number", "account no", "account" ],
        contains: [ "account number", "account no", "bank account" ]
      }
    }.freeze

    TSV_HEADERS = FIELDS.each_value.map { |spec| spec[:label] }.freeze

    # The template's second row. A sheet still carrying it has that row skipped, or its
    # words would read as a claim with an unreadable amount.
    TEMPLATE_HINTS = FIELDS.each_value.map { |spec| spec[:hint] }.freeze

    # The columns a sheet must carry. The submitter is required too, but either of its
    # two columns will do (#report_missing_columns).
    REQUIRED_FIELDS = %i[reference status budget amount].freeze

    # Columns whose CELL every row must fill, unlike REQUIRED_FIELDS (columns the sheet
    # must carry). The cell rules are ExpenseForm's; #required_cell_labels is what the
    # form prints, so the copy cannot call one of these optional.
    REQUIRED_CELL_FIELDS = %i[reference status budget amount description payment_reference].freeze

    # Already paid, or never will be: what ExpenseForm#settled? reads. Stated as the
    # settled set, so a status added later counts as live and gets the stricter rule.
    SETTLED_STATUSES = [ Status::SUBMITTED, Status::PAID, Status::REJECTED ].freeze

    # expenses.import_key is string(255). Checked here so an over-long ID is a row error,
    # not a ValueTooLong 500 inside the wizard's Turbo Frame with the paste lost.
    IMPORT_KEY_LIMIT = 255

    def self.required_labels
      REQUIRED_FIELDS.map { |field| FIELDS.fetch(field)[:label] }
    end

    def self.required_cell_labels
      REQUIRED_CELL_FIELDS.map { |field| FIELDS.fetch(field)[:label] }
    end

    attr_reader :entries, :financial_year, :cost_centre

    # +input_type+ is :paste, :xlsx, or :canonical_tsv: this class's own #to_tsv output
    # coming back from the preview's hidden field. Only that is unescaped; doing it to a
    # paste rewrote a typed "C:\temp\report.pdf" with a real tab.
    def initialize(data, input_type:, financial_year:, cost_centre:, budgets: [], people: [],
                   existing_expenses: [])
      @errors = []
      @financial_year = financial_year
      @cost_centre = cost_centre
      @escaped = input_type == :canonical_tsv
      # Grouped under BOTH spellings (BudgetImport's, so the importers agree on a budget's
      # name), never index_by: it kept the last of same-named lines in different areas,
      # charging a settled claim to an arbitrary show.
      @budgets_by_name = budgets.each_with_object({}) do |budget, index|
        BudgetImport.name_spellings(budget.name, budget.area&.name).each do |spelling|
          (index[BudgetImport.match_key(spelling)] ||= []) << budget
        end
      end
      # Payees with no email are left out: they all index under "", so a blank cell
      # matched whichever came last (140 claims went to Fringe Society).
      @people_by_email = people.select { |person| person.email.present? }
                               .index_by { |person| person.email.strip.downcase }
      @people_by_name = people.group_by { |person| self.class.name_key(person.name) }
      @imported_keys = existing_expenses.filter_map { |e| self.class.key_match(e.import_key) }.to_set
      @taken_numbers = existing_expenses.filter_map(&:auto_number).to_set
      @rows = parse_data(data, @escaped ? :paste : input_type)
                .reject { |row| row[:reference] == FIELDS[:reference][:hint] }
      @entries = categorize
    end

    # Compared as the UNIQUE index does: import_key is utf8mb4_unicode_ci, so "OLD-1" and
    # "old-1" are one key. Accents are deliberately NOT folded though the collation folds
    # them: a sheet mixing "réf-1" and "ref-1" still dead-ends (#apply's rescue names the
    # fix), but over-matching would drop a new claim as already imported.
    def self.key_match(value) = value.to_s.strip.downcase.presence

    def self.name_key(value) = I18n.transliterate(value.to_s).downcase.squish.presence

    def valid?
      @errors.empty? && @entries.any? && @entries.none? { |entry| entry.bucket == :invalid }
    end

    def entries_in(bucket) = @entries.select { |entry| entry.bucket == bucket }

    # Attributes for each new claim, ready for DatabaseStore#import_expenses!.
    def creates
      entries_in(:create).map(&:attrs)
    end

    # Creates at a status the portal still acts on, which the preview warns about.
    def live_entries
      entries_in(:create).reject { |entry| SETTLED_STATUSES.include?(entry.row[:status]) }
    end

    private

    # An unreadable value is carried on verbatim: the preview re-renders from this text
    # after a blocked apply, and a blank would hide the cell the operator has to fix.
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

    # One normalised row per sheet line, called by ImportParsing's parsers. Nil for a
    # wholly blank line, so trailing padding isn't reported as nameless claims.
    def normalize_row(raw)
      @header_for ||= resolve_headers(raw.keys)
      return nil if raw.values.all?(&:blank?)

      row = FIELDS.each_key.to_h { |field| [ field, text(raw, field) ] }
      { amount: :parse_amount, amount_excl_vat: :parse_amount, submitted_on: :parse_date,
        paid_on: :parse_date, auto_number: :parse_number }.each do |field, parser|
        raw = row[field]
        row[field] = send(parser, raw)
        row[:"raw_#{field}"] = raw if row[field] == :unreadable
      end
      row[:payee_email] = row[:payee_email].downcase
      row[:status] = normalize_status(row[:status])
      row[:expense_type] = normalize_type(row[:expense_type])
      row
    end

    # Escape sequences are undone only for #to_tsv output, never the operator's paste.
    def text(raw, field)
      value = raw[header_for[field]].to_s.strip
      @escaped ? unescape_cell(value) : value
    end

    # --- Which column is which -----------------------------------------------

    def parse_number(raw)
      Integer(raw, 10) if raw.present?
    rescue ArgumentError
      :unreadable
    end

    def parse_date(raw)
      value = raw.to_s.strip
      return nil if value.blank?

      Date.parse(value)
    rescue Date::Error
      :unreadable
    end

    # Case-insensitive, so "paid" lands where the operator meant it.
    def normalize_status(raw)
      return nil if raw.blank?

      Status.all.find { |status| status.casecmp?(raw) } || raw
    end

    def normalize_type(raw)
      return Expense::TYPE_REIMBURSEMENT if raw.blank?
      # The stored name carries "(utility, staff cost, etc)", which nobody types.
      return Expense::TYPE_FROM_EUSA if raw.casecmp?("from eusa")

      Expense::TYPES.find { |type| type.casecmp?(raw) } || raw
    end

    # --- Categorisation ------------------------------------------------------

    def categorize
      return [] if @rows.empty?

      # A problem with the sheet is one problem, not thirty broken lines.
      report_ambiguous_columns
      report_missing_columns
      return [] if @errors.any?

      duplicated = duplicated_values
      @rows.map { |row| entry_for(row, duplicated) }
    end

    def report_missing_columns
      missing = REQUIRED_FIELDS.reject { |field| header_for[field] }
                               .map { |field| FIELDS.fetch(field)[:label] }
      missing << "Submitter email or Submitter" unless header_for[:payee_email] || header_for[:submitter_name]
      return if missing.empty?

      @errors << "The sheet has no #{missing.to_sentence} column#{'s' if missing.many?}. " \
                 "Every claim needs #{missing.many? ? 'those' : 'that'}. Start from the " \
                 "template if you're not sure of the headings."
    end

    def entry_for(row, duplicated)
      people = people_for(row)
      person = people.first if people.one?
      candidates = budgets_named(row[:budget])
      budget = candidates.first if candidates.one?
      unknown_submitter = people.empty? && (row[:payee_email].present? || row[:submitter_name].present?)
      base = { row: row, person: person, budget: budget, unknown_submitter: unknown_submitter }

      error = reference_error(row, duplicated)
      return Entry.new(**base, bucket: :invalid, error: error) if error

      # Skipped whatever else is wrong with it, and before the expense number is checked:
      # the claim it created earlier holds that number.
      if @imported_keys.include?(self.class.key_match(row[:reference]))
        return Entry.new(**base, bucket: :already_imported)
      end

      error = row_error(row, people, budget, candidates, duplicated)
      return Entry.new(**base, bucket: :invalid, error: error) if error

      form = form_for(row, budget)
      unless form.valid?
        return Entry.new(**base, bucket: :invalid,
                         error: form.errors.full_messages.to_sentence)
      end

      Entry.new(**base, bucket: :create, attrs: attrs_for(row, form, person))
    end

    # What a row to be created can be wrong about before the form sees it, most fundamental first.
    def row_error(row, people, budget, candidates, duplicated)
      status_error(row) ||
        (submitter_error(row, people) unless people.one?) ||
        (ambiguous_budget_error(row, candidates) if candidates.many?) ||
        (budget_error(row) if budget.nil?) ||
        value_error(row) ||
        auto_number_error(row, duplicated)
    end

    def reference_error(row, duplicated)
      if row[:reference].blank?
        "This line has no ID. Give every claim one (its row number in your own sheet " \
          "will do). It's what stops a second import creating the same claim twice."
      elsif row[:reference].length > IMPORT_KEY_LIMIT
        "That ID is too long: #{row[:reference].length} characters, and the limit is " \
          "#{IMPORT_KEY_LIMIT}."
      elsif duplicated[:references].include?(self.class.key_match(row[:reference]))
        "The ID #{row[:reference].inspect} is used by more than one line in this sheet, so a " \
          "re-import couldn't tell them apart. (IDs are matched ignoring case.)"
      end
    end

    def status_error(row)
      if row[:status].blank?
        "This line has no status. Say what state the claim is in: " \
          "#{Status.all.to_sentence(last_word_connector: ' or ')}."
      elsif Status.all.exclude?(row[:status])
        "#{row[:status].inspect} isn't a status. Use " \
          "#{Status.all.to_sentence(last_word_connector: ' or ')}."
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

    # Nobody is auto-created from a bare email: a person named by their address is what
    # the unique index on Person#email exists to stop, and a claim paid to a stub has
    # nowhere to send the money.
    def submitter_error(row, people)
      if row[:payee_email].blank? && row[:submitter_name].blank?
        "This line names no submitter. Give the email or the name of the person the claim " \
          "belongs to."
      elsif people.many?
        "#{row[:submitter_name].inspect} is the name of more than one person on the People " \
          "screen. Give their email instead."
      else
        "#{(row[:payee_email].presence || row[:submitter_name]).inspect} isn't anyone on the " \
          "People screen. Register them there first: an import never creates anyone."
      end
    end

    def people_for(row)
      return Array(@people_by_email[row[:payee_email]]) if row[:payee_email].present?

      key = self.class.name_key(row[:submitter_name])
      key ? @people_by_name.fetch(key, []) : []
    end

    def budgets_named(name)
      @budgets_by_name.fetch(BudgetImport.match_key(name), [])
    end

    def ambiguous_budget_error(row, candidates)
      "#{row[:budget].inspect} matches more than one budget in #{destination_label} " \
        "(#{BudgetImport.budget_labels(candidates).to_sentence(last_word_connector: ' and ')}). " \
        "#{ambiguous_budget_fix(candidates)}"
    end

    # The suggestion is asked of the index, not assumed: "Cogito: Marketing" resolves
    # nothing when two areas are both called Cogito, and a fix that reproduces the same
    # block is worse than none. A budget with no area has no spelling of its own.
    def ambiguous_budget_fix(candidates)
      spelling = candidates.filter_map { |budget| budget.display_name if budget.area }
                           .find { |candidate| budgets_named(candidate).one? }
      return "Rename one of them, so this sheet can tell them apart." if spelling.nil?

      "Write the one you mean as #{spelling.inspect}, or rename a budget so the two differ."
    end

    def budget_error(row)
      if row[:budget].blank?
        "This line names no budget, so there's nothing to charge it to."
      else
        "#{row[:budget].inspect} isn't a budget in #{destination_label}. Check the spelling, or " \
          "import the budget sheet first."
      end
    end

    # An explicit number is honoured, so a historical claim keeps its number. But
    # create_expense! does not retry past a collision on a number it was handed (it calls
    # that data corruption), so the unique index's collision is reported by row here.
    def auto_number_error(row, duplicated)
      number = row[:auto_number]
      if number == :unreadable
        "#{row[:raw_auto_number].inspect} isn't an expense number."
      elsif duplicated[:numbers].include?(number)
        "Expense number #{number} is used by more than one line in this sheet."
      elsif @taken_numbers.include?(number)
        "Expense number #{number} already belongs to another claim in the portal."
      end
    end

    def duplicated_values
      references = @rows.filter_map { |row| self.class.key_match(row[:reference]) }
                        .tally.select { |_ref, count| count > 1 }.keys.to_set
      numbers = @rows.map { |row| row[:auto_number] }.grep(Integer)
                     .tally.select { |_number, count| count > 1 }.keys.to_set
      { references: references, numbers: numbers }
    end

    def destination_label = "#{financial_year.label} / #{cost_centre.name}"

    # The form the submission and finance-edit screens use, so the importer enforces the
    # same rules, not a restatement that can drift. `internal` is set as
    # ExpenseForm.from_actual sets it: no receipt, no itemised VAT, nobody to tick a soft block.
    def form_for(row, budget)
      ExpenseForm.new(
        expense_type: row[:expense_type],
        internal: true,
        settled: SETTLED_STATUSES.include?(row[:status]),
        budget_record_id: budget.record_id,
        amount: row[:amount]&.to_s("F"),
        # A blank ex-VAT charges the whole amount, as ExpenseForm.from_actual does; nil
        # would fail the presence rule and read as a broken row.
        amount_excl_vat: (row[:amount_excl_vat] || row[:amount])&.to_s("F"),
        description: row[:description],
        payment_reference: row[:payment_reference],
        payee_name_override: row[:payee_name_override],
        sort_code_override: row[:sort_code_override],
        account_number_override: row[:account_number_override]
      )
    end

    # The form's parsed attributes plus the columns only an import writes. create_attrs is
    # read, not the row: AR casts a String to a decimal with #to_d, so a validated
    # "£1,200" passed through would store 0. The status is merged over the form's own
    # (only ever Draft or Pending), as the actuals conversion merges Paid.
    def attrs_for(row, form, person)
      # compact: a blank expense-number cell leaves auto_number out, so the store numbers the claim.
      form.create_attrs(person.record_id).merge(
        status: row[:status],
        import_key: row[:reference],
        auto_number: row[:auto_number],
        financial_year: financial_year,
        payment_confirmed_date: row[:paid_on],
        submitted_at: row[:submitted_on]&.beginning_of_day
      ).compact
    end
  end
end
