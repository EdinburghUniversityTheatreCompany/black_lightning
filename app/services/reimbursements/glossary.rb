module Reimbursements
  ##
  # The words this portal is built on, defined ONCE.
  #
  # There was no glossary anywhere, and the portal's best explanations were
  # `title=` tooltips — invisible on a touch screen and to the keyboard, and
  # present on some screens and not others. Worse, the same idea went by two or
  # three names: claim and expense, endorse and sign-off, update and forecast
  # and revision. For a job that changes hands every year that is most of what
  # a successor has to learn.
  #
  # The definitions live here rather than in the glossary view because the
  # budget screens print a subset of them inline (the money columns, where the
  # reader is), and a column note that had drifted from the glossary would be
  # worse than neither. Each entry names the reader it is written for and,
  # where a figure has a rule that surprises people, states the rule — these
  # are the words, not a paraphrase of them.
  module Glossary
    Term = Struct.new(:key, :term, :definition, :also, keyword_init: true)

    # The money columns, in the order a line is read left to right. The budget
    # screens render exactly this list under "What these columns mean".
    MONEY = [
      Term.new(key: :initial_budget, term: "Initial budget",
               definition: "The figure agreed when the line was set up, either from the " \
                           "committee's spreadsheet or typed in when the line was created. " \
                           "It is never rewritten by a later revision, so it stays the thing " \
                           "a plan is measured against."),
      Term.new(key: :projected, term: "Projected",
               definition: "The line's current plan: the latest forecast logged against it, " \
                           "falling back to the initial budget when none has been. Marked " \
                           "\"(initial)\" where it is falling back.",
               also: "the plan, the current forecast"),
      Term.new(key: :committed, term: "Committed",
               definition: "Claims that are Approved, Submitted or Paid. Money the theatre has " \
                           "agreed to spend, whether or not it has left the account yet."),
      Term.new(key: :pipeline, term: "Pipeline",
               definition: "Claims still Pending: asked for, not yet approved. Kept apart from " \
                           "Committed so Committed keeps its meaning.",
               also: "waiting for approval"),
      Term.new(key: :remaining, term: "Remaining",
               definition: "The plan less what is Committed. It deliberately IGNORES the " \
                           "pipeline, because this is the figure finance reads when deciding " \
                           "whether a line is overspent. Blank, never £0, when nobody set a " \
                           "plan: a zero there would read as \"fully spent\"."),
      Term.new(key: :left, term: "Left",
               definition: "The plan less what is Committed AND what is waiting for approval. " \
                           "A different question from Remaining, and the one an owner is " \
                           "asking: can my show still afford this? Money a producer has " \
                           "already claimed is spent as far as that goes.",
               also: "on My Budgets and an area's page"),
      Term.new(key: :expected_outturn, term: "Expected outturn",
               definition: "The most this line could realistically end up costing: the greater " \
                           "of the current plan and what has already been spent or committed, " \
                           "so it never drops below reality. Blank on an income line, where the " \
                           "same figure would read as best-case income instead."),
      Term.new(key: :variance, term: "Variance",
               definition: "How far the current plan has drifted from the initial budget. £0.00 " \
                           "with no forecast logged, because the plan then IS the agreed figure; " \
                           "blank only when no initial budget was ever set."),
      Term.new(key: :eusa_actual, term: "EUSA actual",
               definition: "What EUSA's own ledger says landed on this line, net of credits. " \
                           "It is read off their monthly export, not from anything the " \
                           "portal did. Its divergence from Paid is the signal that something " \
                           "needs reconciling.")
    ].freeze

    # How the money is organised.
    STRUCTURE = [
      Term.new(key: :area, term: "Area",
               definition: "The show, festival or committee a set of budget lines belongs to. " \
                           "It holds one agreed total and one set of owners, and its lines " \
                           "inherit both. A line with no area stands on its own.",
               also: "a show, a project"),
      Term.new(key: :cost_centre, term: "Cost centre",
               definition: "One pot of money, with its own budgets, claims, ledger rows, " \
                           "batches and mailboxes. Bedlam Fringe and the termtime theatre are " \
                           "separate pots. Choosing none on a screen means every pot, never " \
                           "one of them."),
      Term.new(key: :financial_year, term: "Financial year",
               definition: "One year's set of budgets. Exactly one year is ACTIVE at a time, " \
                           "and that is the one submitters file against; next year is built as " \
                           "a draft alongside it and switched to when it is ready."),
      Term.new(key: :nominal_code, term: "Nominal code",
               definition: "EUSA's account code for a kind of spending (432320, 439999). " \
                           "SEVERAL budget lines can share one, which is why every figure in " \
                           "this portal is linked line by line rather than matched on the code."),
      Term.new(key: :budget_update, term: "Forecast revision",
               definition: "A revision of the plan, logged with a date and a reason so the " \
                           "history survives. One revision can cover several lines at once (a " \
                           "budget meeting's worth) and can be opened and undone as a unit.",
               also: "budget update, forecast")
    ].freeze

    # How a claim moves, in the order it moves.
    CLAIMS = [
      Term.new(key: :claim, term: "Claim",
               definition: "One request for money: a producer's receipt, a supplier's invoice, " \
                           "or a cost EUSA levied directly. The words claim and expense mean " \
                           "the same thing here.",
               also: "expense"),
      Term.new(key: :endorse, term: "Endorse",
               definition: "A budget owner confirming a claim charged to their line before " \
                           "finance pays it. Any one owner can; a claim an owner filed " \
                           "themselves clears automatically; finance can override with a note " \
                           "when no owner has a portal account.",
               also: "owner sign-off, sign-off"),
      Term.new(key: :statuses, term: "Draft, Pending, Approved, Submitted, Paid, Rejected",
               definition: "A claim's life. Pending means it is waiting on an owner or on " \
                           "finance; Approved means finance has agreed it and it will go in the " \
                           "next batch; SUBMITTED means it has gone to EUSA, not that the " \
                           "producer submitted it; Paid means a ledger row has confirmed it."),
      Term.new(key: :batch, term: "Batch",
               definition: "One BACS submission to EUSA: a spreadsheet of the approved claims " \
                           "plus a covering email, left as a DRAFT in the cost centre's Outlook " \
                           "for a person to send. Sending it is the one step the portal does " \
                           "not do."),
      Term.new(key: :bacs_date, term: "BACS date",
               definition: "The payment date typed on the build form: what EUSA is asked to " \
                           "pay on. It is not a record that anything was sent; nothing in the " \
                           "portal records the manual send.")
    ].freeze

    # The EUSA ledger, which is where the money is checked afterwards.
    LEDGER = [
      Term.new(key: :actuals, term: "Actuals",
               definition: "EUSA's own ledger export, imported monthly. One row per transaction " \
                           "that actually hit the account, and the record against which " \
                           "everything the portal believes is checked.",
               also: "the EUSA ledger"),
      Term.new(key: :reconcile, term: "Reconcile",
               definition: "Matching a month's actuals export to the claims the portal already " \
                           "holds, so each one is marked Paid and each line's figures come from " \
                           "the bank rather than from what was requested."),
      Term.new(key: :offsetting_pair, term: "Offsetting pair",
               definition: "An accrual and the reversal that cancels it. Together they net to " \
                           "zero, so NEITHER is real spend and both are left out of every " \
                           "total. They stay on the ledger, because finance needs the audit " \
                           "trail."),
      Term.new(key: :unattributed, term: "Unlinked",
               definition: "A ledger row no budget's figures account for: attached to no claim, " \
                           "booked against no income line, and not one leg of an offsetting " \
                           "pair. Until it is linked, that money is missing from every budget " \
                           "total.",
               also: "unattributed, needs attention"),
      Term.new(key: :apportion, term: "Split across budgets",
               definition: "Dividing one credit between several income lines. A Stripe payout " \
                           "covering a week of shows lands as a single row, and without this " \
                           "the whole of it would count as one show's income.")
    ].freeze

    SECTIONS = [
      [ "How the money is organised", STRUCTURE ],
      [ "The money columns", MONEY ],
      [ "How a claim moves", CLAIMS ],
      [ "The EUSA ledger", LEDGER ]
    ].freeze

    ALL = SECTIONS.flat_map(&:last).freeze

    # The terms a screen names, in the order given, for the inline "what these
    # columns mean" block. Raises on an unknown key rather than silently
    # printing a shorter list: a column left unexplained is the whole failure
    # this exists to fix.
    def self.terms(*keys)
      keys.map do |key|
        ALL.find { |term| term.key == key } ||
          raise(ArgumentError, "no glossary term #{key.inspect}")
      end
    end
  end
end
