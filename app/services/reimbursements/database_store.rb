module Reimbursements
  # The ActiveRecord-backed repository: the single data gateway every controller and job talks
  # to (built by Reimbursements.build_store). Lists are memoized per instance (one store per
  # request or job run), so repeated reads in one render cost one query.
  #
  # Writers take the attribute vocabulary (person_record_id/budget_record_id/batch_id strings,
  # an array for sharepoint_receipt_urls); nil values are dropped so email-in claims can be
  # created with gaps.
  class DatabaseStore
    # Raised instead of removing an expense's last receipt (drafts excepted).
    class LastReceiptError < StandardError; end

    # The ledger row stopped being convertible between the caller's check and the write.
    class NotConvertibleError < StandardError; end

    # The budget an expense names was deleted while its form was open (Honeybadger 134234926).
    # Named so controllers re-render the form instead of 500ing and losing a filled-in claim.
    class BudgetGoneError < StandardError; end

    # A claim, ledger row or split credit names the budget being deleted.
    class BudgetInUseError < StandardError; end

    # The ledger row stopped being splittable between the caller's check and the write.
    class NotApportionableError < StandardError; end

    # Shares that do not sum to the row they divide. A short split understates income with
    # nothing on screen saying so, so the write is refused whole.
    class ApportionmentMismatchError < StandardError; end

    # The claim exists only because of this ledger row (a From-EUSA claim), so there is no
    # earlier state to unlink it to. Delete the claim instead.
    class ClaimFromRowError < StandardError; end

    # A ledger row may not settle this claim: nobody agreed to pay a draft or a rejected claim,
    # and a Paid claim already settled would count the charge twice.
    class NotSettleableError < StandardError
      attr_reader :status

      def initialize(status)
        @status = status
        super("the claim is #{status}, so this row can't settle it")
      end
    end

    # A row shared across claims (#share_actual!) or a further part of one (#add_part_payment!)
    # was refused; the message is the operator's reason, worded for the screen.
    class ShareRefusedError < StandardError; end
    class PartRefusedError < StandardError; end

    # Bucket label for budgets with a blank nominal code in the overview.
    NO_CODE_LABEL = "(none)".freeze

    # The year the budget screens are scoped to; nil for an unscoped store (jobs, producer
    # surfaces). Set once at construction: one store per request.
    attr_reader :financial_year

    # The cost centre the finance screens are scoped to; nil means every centre (unscoped
    # stores, and a finance page with no ?cost_centre=).
    attr_reader :cost_centre

    def initialize(financial_year: nil, cost_centre: nil)
      @financial_year = financial_year
      @cost_centre = cost_centre
    end

    # Vocabulary keys that differ from their AR column; the rest already match.
    EXPENSE_KEY_MAP = { person_record_id: :person_id, budget_record_id: :budget_id }.freeze
    PERSON_FIELDS = %i[name email].freeze
    # Bank fields route to the linked PaymentDetails record; the vocabulary lives on that model.
    PAYMENT_DETAILS_FIELDS = PaymentDetails::FIELDS

    # Preloads the payee's payment_details (every BACS/attention check reads the effective bank
    # details, so a 150-payee workbook paid 150 queries) and the budget's area
    # (Budget#display_name reads it).
    def expenses
      @expenses ||= Expense.includes(:batch, budget: :area, person: :payment_details)
                           .with_attached_receipt_files.to_a
    end

    # The selected centre's expenses, for the screens. Lenient: an unplaced claim shows under
    # every centre. The money path must not read it this way, see #expenses_owned_by_cost_centre.
    def expenses_for_cost_centre
      in_cost_centre(expenses, cost_centre)
    end

    # Every claim +centre+ is responsible for paying: what Build Batch reads.
    #
    # THE RULE: a read-only filter may be lenient, but anything that moves money assigns each
    # claim to exactly one centre. BuildBatchJob's limits_concurrency key is per centre, so a
    # claim visible to two centres reaches two live EUSA drafts and EUSA pays twice. An unplaced
    # claim falls to the DEFAULT centre. NightlyBatchJob reads this too, so the centre reminded
    # about a claim is the centre that can pay it.
    #
    # Raises on a nil centre: "no centre" cannot mean "every centre" here, and [] would
    # silently build an empty batch.
    def expenses_owned_by_cost_centre(centre)
      raise ArgumentError, "a batch is built for one cost centre; none was given" if centre.nil?

      default_id = CostCentre.default&.id
      expenses.select { |expense| (expense.cost_centre_id || default_id) == centre.id }
    end

    def expenses_for(person_record_id)
      return [] if person_record_id.blank?

      expenses.select { |e| e.person&.record_id == person_record_id }
              .sort_by { |e| e.submitted_at || Time.zone.at(0) }
              .reverse
    end

    def find_expense(record_id)
      Expense.includes(:person, :batch, budget: :area).find_by(id: record_id)
    end

    def find_person(record_id)
      Person.includes(:payment_details).find_by(id: record_id)
    end

    def person_by_email(email)
      return nil if email.blank?

      people.find { |p| p.email.to_s.strip.casecmp?(email.strip) }
    end

    def find_budget(record_id)
      Budget.includes(:forecasts, :own_owners, area: :owners).find_by(id: record_id)
    end

    # Preloads what the area edit page's figures read (Area#committed_amount, #allocated per
    # budget line).
    def find_area(record_id)
      # Every figure the area page reads, Paid by EUSA and Received included.
      Area.includes(:owners, :forecasts,
                    budgets: [ :forecasts, :actual_allocations, :eusa_actuals,
                               { expenses: %i[eusa_actuals claim_share] } ]).find_by(id: record_id)
    end

    def find_batch(record_id)
      Batch.find_by(id: record_id)
    end

    # By name, blanks last, id as tiebreak. Ordered in SQL because the column collates
    # utf8mb4_unicode_ci, which folds accents while Ruby's sort is byte-wise ("Ábel" would land
    # after "Zoe", unlike every other ordered list in the portal).
    def people
      @people ||=
        Person.includes(:payment_details)
              .order(Arel.sql("CASE WHEN name IS NULL OR name = '' THEN 1 ELSE 0 END"), :name, :id)
              .to_a
    end

    # The owner sign-off (or finance override) covering one claim, or nil.
    def endorsement_for_expense(record_id)
      OwnerEndorsement.includes(:overridden_by).for_expense(record_id).first
    end

    # The same for many claims in one query: the Review queue draws a chip per card.
    def endorsements_by_expense(record_ids)
      return {} if record_ids.empty?

      OwnerEndorsement.includes(:overridden_by)
                      .where(expense_record_id: record_ids).index_by(&:expense_record_id)
    end

    # Claims submitted per person, keyed by record id, in one grouped query: the People index
    # would otherwise count per row.
    def expense_counts_by_person_id
      @expense_counts_by_person_id ||=
        Expense.where.not(person_id: nil).group(:person_id).count
               .transform_keys(&:to_s)
    end

    # Memoized so the exporters' id->centre lookup costs one query however many rows name one.
    def cost_centres
      @cost_centres ||= CostCentre.order(:name).to_a
    end

    # Every budget, every financial year, WITHOUT the actuals preload: the producer's budget
    # <select>, the review queue and the nightly job only want names and forecasts, and the
    # ledger costs six queries plus the whole expenses table in memory.
    #
    # Deliberately not year-scoped either. Callers are id->budget lookups (Review, the expenses
    # index, every export, the nightly job) and the reconcile matcher: scoping would blank the
    # budget name on last year's claims, and the matcher picks each credit's year from the credit's
    # own date. Screens that list a year's budgets use #budgets_for_year.
    def budgets
      @budgets ||= Budget.includes(:forecasts, :own_owners, :cost_centre, area: %i[owners cost_centre]).to_a
    end

    # The selected year's budgets, for the budget screens. An unscoped store sees every budget,
    # as a database whose rows predate financial years needs.
    def budgets_for_year
      @budgets_for_year ||= scoped(budgets)
    end

    # Budgets with EUSA actuals preloaded (directly for income credits, through expenses for
    # debit legs), so the per-line rollup in the budgets index/overview and the Budgets export
    # costs no per-budget query. Year-scoped.
    def budgets_with_actuals
      @budgets_with_actuals ||= scoped(
        Budget.includes(:forecasts, :own_owners, :eusa_actuals, :actual_allocations,
                        area: :owners, expenses: %i[eusa_actuals claim_share]).to_a
      )
    end

    # Budgets a submitter may charge: from the ACTIVE year, never the selected one, so a finance
    # user browsing next year's draft cannot file against it.
    #
    # Deliberately not cost-centre scoped: this is the submitter's picker, shared with Review's
    # picker, the actuals conversion and the finance expense-edit form, and narrowing it to the
    # selected centre would stop a producer filing against the other one. Sorted by the label
    # the pickers print (Budget#display_name); ExpenseForm validates the ids it rendered, never
    # a position.
    def active_budgets
      in_year(budgets, FinancialYear.current).select { |b| b.active && !b.income? }.sort_by(&:display_name)
    end

    # The producer's picker only. Finance's pickers read #active_budgets so a
    # hidden centre's claims stay editable; a line with no centre stays offered.
    def submittable_budgets
      active_budgets.reject { |b| b.cost_centre&.hidden_from_submitters? }
    end

    # Every area, every year: an id->record lookup, unscoped for #budgets' reason. Preloads each
    # budget's expenses, forecasts and allocations plus the area's own forecasts, because
    # Area#committed_amount, #allocated and #projected_amount read them per budget per area
    # (an N+1 on every areas index or grouped budgets index otherwise).
    def areas
      @areas ||= Area.includes(:owners, :forecasts,
                               budgets: %i[expenses forecasts actual_allocations]).to_a
    end

    # My Budgets' Paid by EUSA (Budget#eusa_actual_amount) reads each claim's ledger rows. Loaded
    # for the owner's budgets only: store.areas' other callers never read them.
    def preload_paid_by_eusa(budgets)
      ActiveRecord::Associations::Preloader.new(
        records: budgets, associations: { expenses: %i[eusa_actuals claim_share] }
      ).call
      budgets
    end

    # The areas the budget screens list.
    def areas_for_year
      @areas_for_year ||= scoped(areas)
    end

    # Grouped by nominal code for the overview, blank-code bucket ("(none)") last. Built from
    # #budgets_with_actuals, so the grouped totals cost no extra queries.
    def budgets_by_nominal_code
      budgets_with_actuals.group_by { |b| b.nominal_code.presence || NO_CODE_LABEL }
             .sort_by { |code, _| [ code == NO_CODE_LABEL ? 1 : 0, code ] }
             .to_h
    end

    # EUSA ledger rows no budget's figures account for: linked to no expense (how an Expense
    # budget reaches its actuals) or budget (an Income budget's credits), and not a leg of an
    # offsetting pair (which nets to zero).
    #
    # Linkage-based, not nominal-code based: budgets can share a code, so a code-based list would
    # hide an unlinked row behind any budget sharing it, which is the spend this list exists to
    # surface. An apportioned row is excluded too: it carries no budget_id, so without that every
    # split row would reappear as unlinked income and the card would be a permanent false alarm.
    # Sorted by code then date, so finance can see which budget a row probably belongs to.
    def unattributed_actuals
      eusa_actuals_for_cost_centre
        .select(&:needs_attention?)
        .sort_by { |a| [ a.nominal_code.to_s, a.date || Date.new(0), a.id ] }
    end

    def update_budget!(record_id, attrs)
      budget = Budget.find(record_id)
      # Not attrs.compact: area_id may be a deliberate nil (detach), and compact would drop the
      # key. initial_budget is left out of the hash when unset rather than sent as nil.
      attrs = attrs.dup
      owner_ids = attrs.delete(:owner_ids)
      budget.update!(attrs)
      budget.sync_owner_ids!(Array(owner_ids).reject(&:blank?)) unless owner_ids.nil?
      bust_budgets!
      budget
    end

    # Deletes a line nothing names, with its forecasts and owner rows. Checked under the row
    # lock: a claim saved meanwhile waits on it, then fails as BudgetGoneError. Without the check
    # destroy! would still succeed, as dependent: :nullify silently unlinks claims and ledger rows.
    def delete_budget!(record_id)
      Budget.transaction do
        budget = Budget.lock.find(record_id)
        raise BudgetInUseError unless budget.deletable?

        budget.destroy!
      end
      bust_budgets!
    end

    def create_area!(attrs)
      area = Area.create!(attrs.compact)
      bust_areas!
      area
    end

    # REPLACE semantics, the area form's write, where removing an owner is intended.
    # #add_area_owners! only adds.
    def sync_area_owners!(record_id, person_ids)
      Area.find(record_id).sync_owner_ids!(Array(person_ids).reject(&:blank?))
      bust_areas!
    end

    # What an applied budget import did, for the confirmation screen.
    ImportResult = Struct.new(:created, :revised, :owners_synced, :budget_update, :areas_created,
                              :re_homed, :area_owners_synced, :area_revised, keyword_init: true)

    # Applies a confirmed BudgetImport: creates the new lines, logs the revised figures as ONE
    # budget update (so they reach the forecast history with the import as the note) and
    # re-syncs owners on existing lines.
    #
    # All-or-nothing, unlike the reconcile wizard's per-row rescue: a half-imported list has no
    # audit value and no obvious repair, while re-running after a fix is cheap because matching
    # is by name. Areas are created first, so a creates/re_homes entry carrying +area_name:+ has
    # an id to resolve to.
    def import_budgets!(creates:, revisions:, owner_syncs:, note:, created_by:, adoptions: [],
                        area_creates: [], re_homes: [], area_owner_syncs: [], area_revisions: [])
      result = Budget.transaction do
        areas_by_name = area_creates.to_h do |attrs|
          [ ::Reimbursements::BudgetImport.match_key(attrs[:name]), create_area!(attrs) ]
        end
        created = creates.map { |attrs| create_budget!(resolve_area(attrs, areas_by_name)) }
        adoptions.each { |adoption| adopt_budget!(adoption[:budget_id], adoption[:cost_centre]) }
        re_homes.each do |re_home|
          re_home_budget!(re_home[:budget_id], resolve_area_id(re_home, areas_by_name))
        end
        owner_syncs.each { |sync| sync_budget_owners!(sync[:budget_id], sync[:owner_ids]) }
        area_owners_synced = 0
        area_owner_syncs.each do |sync|
          area_id = resolve_optional_area_id(sync, areas_by_name)
          next if area_id.nil?

          add_area_owners!(area_id, sync[:owner_ids])
          area_owners_synced += 1
        end
        # One update for both levels: a committee meeting revises an area's total and its
        # lines' allocations together.
        forecasts = revisions + area_revisions
        update = if forecasts.any?
                   create_budget_update!(effective_date: Date.current, note: note,
                                         created_by: created_by, forecasts: forecasts)
        end
        ImportResult.new(created: created.size, revised: revisions.size,
                         owners_synced: owner_syncs.size, budget_update: update,
                         areas_created: areas_by_name.size, re_homed: re_homes.size,
                         area_owners_synced: area_owners_synced,
                         area_revised: area_revisions.size)
      end
      bust_budgets!
      bust_areas!
      result
    end

    # One budget line. +owner_ids+ are People ids, synced after the row exists.
    def create_budget!(attrs)
      attrs = attrs.dup
      owner_ids = attrs.delete(:owner_ids)
      budget = Budget.create!(attrs)
      budget.sync_owner_ids!(Array(owner_ids).reject(&:blank?))
      bust_budgets!
      budget
    end

    # Only called for a budget with no cost centre (BudgetImport#adoptions), so it never moves a
    # line out of the pot that owns it.
    def adopt_budget!(record_id, cost_centre)
      budget = Budget.find(record_id)
      budget.update!(cost_centre: cost_centre) if budget.cost_centre_id.nil?
      bust_budgets!
      budget
    end

    # No "only when blank" guard, unlike adopt_budget!: moving a line out of another area is the
    # point, and the operator ticked it against a preview stating "from -> to".
    def re_home_budget!(record_id, area_id)
      budget = Budget.find(record_id)
      budget.update!(area_id: area_id)
      bust_budgets!
      bust_areas!
      budget
    end

    def sync_budget_owners!(record_id, owner_ids)
      budget = Budget.find(record_id)
      budget.sync_owner_ids!(Array(owner_ids).reject(&:blank?))
      bust_budgets!
      budget
    end

    # Only ever ADDS: a spreadsheet cannot say "remove this owner" (a blank cell says nothing),
    # so subtracting would drop a show's sign-off authority silently. Removal is hand-work on the
    # area form (#sync_area_owners!).
    #
    # The union is taken against what the area holds now; BudgetImport#area_owner_syncs compares
    # against the preview's copy. It must stay a union: Area#sync_owner_ids! is a diff sync, so
    # anything short of a superset deletes the difference. The `any?` guard covers the empty
    # list, where `where.not(person_id: [])` is WHERE 1=1.
    def add_area_owners!(record_id, owner_ids)
      area = Area.find(record_id)
      union = area.owner_ids.map(&:to_i) | Array(owner_ids).compact_blank.map(&:to_i)
      area.sync_owner_ids!(union) if union.any?
      bust_areas!
      bust_budgets!
      area
    end

    def budget_forecasts(budget_id)
      return [] if budget_id.blank?

      BudgetForecast.where(budget_id: budget_id).includes(:budget_update)
                    .order(date: :desc, id: :desc).to_a
    end

    def create_forecast!(budget_id:, amount:, date:, reason:)
      forecast = BudgetForecast.create!(budget_id: budget_id, amount: amount,
                                        date: date, reason: reason)
      bust_budgets!
      forecast
    end

    def update_forecast!(record_id, amount:, date:, reason:)
      forecast = BudgetForecast.find(record_id)
      forecast.update!(amount: amount, date: date, reason: reason)
      bust_budgets!
      forecast
    end

    def delete_forecast!(record_id)
      BudgetForecast.find(record_id).destroy!
      bust_budgets!
    end

    # A multi-budget revision in one gesture: a BudgetUpdate carrying the shared date, note and
    # author, and one BudgetForecast per entry (dated and reasoned from it). +forecasts+ holds
    # {budget_id:, amount:} or {area_id:, amount:} entries; the caller drops blank amounts.
    # All-or-nothing.
    def create_budget_update!(effective_date:, note:, created_by:, forecasts:)
      update = BudgetUpdate.transaction do
        # The year being viewed, not just the live one: a revision logged while setting next
        # year's budgets up belongs to next year.
        created = BudgetUpdate.create!(effective_date: effective_date, note: note,
                                       created_by: created_by,
                                       financial_year: financial_year || FinancialYear.current)
        forecasts.each do |entry|
          BudgetForecast.create!(budget_id: entry[:budget_id], area_id: entry[:area_id],
                                 amount: entry[:amount], date: effective_date,
                                 reason: note, budget_update: created)
        end
        created
      end
      bust_budgets!
      update
    end

    # The selected year's budget revisions, newest first.
    def budget_updates
      in_year(BudgetUpdate.includes(:created_by, forecasts: [ :area, { budget: :area } ])
                          .order(effective_date: :desc, id: :desc).to_a, financial_year)
    end

    # Every logged forecast in the selected year and centre, newest first (the Forecast
    # revisions export sheet). Scoped through the OWNER: a forecast belongs to exactly one of a
    # budget or an area and carries neither's year or centre.
    def forecasts_for_scope
      @forecasts_for_scope ||=
        BudgetForecast.includes(budget: :area, area: {}, budget_update: :created_by)
                      .order(date: :desc, id: :desc).to_a
                      .select { |forecast| scoped([ forecast.budget || forecast.area ]).any? }
    end

    # Unscoped like #budgets: an update logged against last year's lines is still openable from
    # a bookmark.
    def find_budget_update(record_id)
      return nil if record_id.blank?

      BudgetUpdate.includes(:created_by, forecasts: %i[budget area]).find_by(id: record_id)
    end

    # Undoes a revision: destroying the update destroys the forecasts it logged (dependent:
    # :destroy), so each line falls back to the forecast before it. One transaction, so no line
    # reverts alone.
    def delete_budget_update!(record_id)
      BudgetUpdate.transaction do
        BudgetUpdate.lock.find(record_id).destroy!
      end
      bust_budgets!
    end

    # Retries the auto_number MAX+1 race: two concurrent creates (portal vs poll job) can pick
    # the same number; the unique index rejects the loser, which re-reads MAX on the retry.
    # An explicit (non-nil) auto_number, as the importer hands over, is never retried: a collision
    # there is real data corruption.
    def create_expense!(attrs)
      attempts = 0
      begin
        expense = Expense.create!(expense_columns(attrs)
                                    .reverse_merge(financial_year: FinancialYear.current))
      rescue ActiveRecord::RecordNotUnique
        raise if attrs[:auto_number] || (attempts += 1) >= 3

        retry
      rescue ActiveRecord::InvalidForeignKey
        raise BudgetGoneError if budget_gone?(attrs)

        raise
      end
      bust_expenses!
      expense
    end

    # Finance's historical-claims sheet as ONE transaction, the all-or-nothing rule of
    # #import_budgets!. ExpenseImport has validated every row, so a raise here is a race
    # (double-submitted apply, two operators) and rolling back makes re-running safe.
    #
    # Rows carrying a number FROM THE SHEET go in first: auto_number is uniquely indexed and
    # create_expense! gives an unnumbered row MAX+1, which could walk into a number a later row is
    # about to claim (and it deliberately does not retry past a collision on a handed number).
    #
    # Nothing here notifies anyone: an import is bookkeeping, and every producer email comes
    # from BatchProcessor, the nightly reminders or an explicit reject.
    def import_expenses!(rows:)
      created = Expense.transaction do
        numbered, unnumbered = rows.partition { |attrs| attrs[:auto_number].present? }
        (numbered + unnumbered).map { |attrs| create_expense!(attrs) }
      end
      bust_expenses!
      created
    end

    # Hard delete, for a producer discarding their own draft; the caller gates on status.
    def delete_expense!(record_id)
      Expense.find(record_id).destroy!
      bust_expenses!
    end

    # A present-and-nil value for these clears the column; for every other column nil means
    # "not edited here" (see #update_expense!). foreign_amount: blanking the invoice amount
    # must not be a no-op that looks like a save. payment_confirmed_date: #unlink_actual_from_expense!
    # must undo the settle it reverses. `amount` is deliberately absent: four other write paths
    # (BatchProcessor, reject, Review#save, the producer form) rely on its "nil means leave it
    # alone" contract.
    CLEARABLE_EXPENSE_COLUMNS = %i[foreign_amount payment_confirmed_date].freeze

    def update_expense!(record_id, attrs)
      expense = Expense.find(record_id)
      columns = expense_columns(attrs)
      # A blank budget_record_id clears the budget; compaction would make it settable only.
      columns[:budget_id] = nil if attrs.key?(:budget_record_id) && attrs[:budget_record_id].blank?
      CLEARABLE_EXPENSE_COLUMNS.each do |key|
        columns[key] = nil if attrs.key?(key) && attrs[key].nil?
      end
      expense.update!(columns)
      bust_expenses!
      expense
    rescue ActiveRecord::InvalidForeignKey
      raise BudgetGoneError if budget_gone?(attrs)

      raise
    end

    def attach_receipt!(expense_record_id, filename:, content_type:, bytes:)
      Expense.find(expense_record_id).receipt_files
             .attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
      bust_expenses!
    end

    # Refuses to leave a non-draft receipt-less. attachment_id is the BLOB id, never the signed
    # id: that is a bearer token for ActiveStorage's unauthenticated routes and must not reach a
    # browser (see Expense.wrap_receipt). Matching is scoped to this expense's own files.
    def remove_receipt!(expense_record_id, attachment_id)
      expense = Expense.find(expense_record_id)
      target = expense.receipt_files.find { |file| file.blob_id.to_s == attachment_id.to_s }
      return if target.nil?

      raise LastReceiptError if !expense.draft? && expense.receipt_files.one?

      target.purge
      bust_expenses!
    end

    # Back to Approved and out of its batch, so it re-enters Build Batch. Leaves
    # producer_notified alone so a rebuild does not re-email the producer.
    def revert_expense_to_approved!(record_id)
      Expense.find(record_id).update!(status: Status::APPROVED, batch_id: nil,
                                      submitted_to_eusa_date: nil, receipts_offloaded: false,
                                      sharepoint_receipt_urls: "")
      bust_expenses!
    end

    def batches
      @batches ||= Batch.order(:id).to_a
    end

    # A Batch has no cost-centre column: it takes its centre from the expenses it holds (a batch
    # is built for one centre). A batch holding nothing, or an unplaced claim, shows under every
    # centre, the leniency #in_cost_centre applies.
    def batches_for_cost_centre
      return batches if cost_centre.nil?

      centre_ids = expenses.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |expense, map|
        map[expense.batch_id] << expense.cost_centre_id if expense.batch_id.present?
      end
      batches.select do |batch|
        ids = centre_ids[batch.record_id]
        ids.empty? || ids.include?(nil) || ids.include?(cost_centre.id)
      end
    end

    def find_batch_by_draft_message_id(message_id)
      return nil if message_id.blank?

      Batch.find_by(draft_message_id: message_id)
    end

    def expense_for_source_message(message_id)
      return nil if message_id.blank?

      Expense.find_by(source_message_id: message_id)
    end

    def create_batch!(attrs)
      batch = Batch.create!(attrs.compact)
      bust_batches!
      batch
    end

    def update_batch!(record_id, attrs)
      batch = Batch.find(record_id)
      batch.update!(attrs.compact)
      bust_batches!
      batch
    end

    def delete_batch!(record_id)
      Batch.find(record_id).destroy!
      bust_batches!
    end

    def create_person!(name:, email:)
      person = Person.create!(name: name, email: email)
      bust_people!
      person
    end

    # Person columns and bank fields arrive mixed; the bank fields go to the linked
    # PaymentDetails record (created on first write).
    def update_person!(record_id, attrs)
      person = Person.find(record_id)
      attrs = attrs.compact
      person.update!(attrs.slice(*PERSON_FIELDS)) if attrs.keys.intersect?(PERSON_FIELDS)
      details_attrs = attrs.slice(*PAYMENT_DETAILS_FIELDS)
      if details_attrs.any?
        details = person.payment_details || person.build_payment_details
        details.update!(details_attrs)
      end
      bust_people!
      person
    end

    def bust_expenses!
      @expenses = nil
    end

    # --- EUSA Actuals (reconciliation) ------------------------------------

    def eusa_actuals
      @eusa_actuals ||= EusaActual.includes(:expense, :budget, allocations: :budget, claim_shares: :expense).to_a
    end

    # The selected centre's ledger rows, for the Actuals browser and its CSV. +eusa_actuals+
    # stays unscoped: it is the reconcile wizard's dedup pool and already-reconciled lookup,
    # which attribute per row and would re-import another centre's rows off a narrowed pool.
    def eusa_actuals_for_cost_centre
      in_cost_centre(eusa_actuals, cost_centre)
    end

    # Actuals already imported for an EUSA period (P1..P12), to dedup a pasted export. Both sides
    # go through Reconciliation.normalise_period: a row that slipped in unpadded (written with
    # update_column or from the console) must still be recognised, or a re-paste double-counts it
    # in the ledger and every rollup.
    def actuals_for_period(period)
      key = Reconciliation.normalise_period(period)
      eusa_actuals.select { |a| Reconciliation.normalise_period(a.period) == key }
    end

    def find_actual(record_id)
      EusaActual.includes(:expense, :budget, allocations: :budget, claim_shares: :expense).find_by(id: record_id)
    end

    # Stamped with the year the row's own date falls in: EUSA's March rows arrive after the
    # switch to the new year and still belong to the old one.
    def create_actual!(attrs)
      attrs = attrs.compact
      actual = EusaActual.create!(attrs.reverse_merge(financial_year: financial_year_for(attrs[:date])))
      bust_eusa_actuals!
      actual
    end

    def link_actual_to_expense!(actual_id, expense_id)
      actual = EusaActual.find(actual_id)
      actual.update!(expense_id: expense_id)
      bust_eusa_actuals!
      actual
    end

    # Links an actual to an expense and settles the claim in one transaction: Paid on the row's
    # date, and an international claim's amount corrected to what EUSA's bank charged. Its stored
    # amount is finance's GBP estimate, and uncorrected every budget rollup quotes it forever
    # (amount_excl_vat follows, as Expense mirrors it on that rail). One method because reconcile
    # apply and the Actuals manual link both do exactly this, and a half-applied settle leaves an
    # actual pointing at a claim still reading Submitted.
    #
    # Raises NotSettleableError for a claim no ledger row may settle (#settleable?), re-read under
    # a row lock: both callers filter first, but their reads go stale and the next caller may not.
    def settle_expense_from_actual!(actual_id, expense_id, payment_date:, gbp_charged: nil)
      settled = EusaActual.transaction do
        expense = Expense.lock.find(expense_id)
        raise NotSettleableError, expense.status unless settleable?(expense, actual_id)

        link_actual_to_expense!(actual_id, expense_id)
        attrs = { status: Status::PAID, payment_confirmed_date: payment_date }
        attrs[:amount] = gbp_charged if gbp_charged && expense.international?
        attrs[:amount_excl_vat] = expense.amount if Reconciliation.vat_not_reclaimed?(expense, gbp_charged)
        update_expense!(expense_id, attrs)
      end
      bust_eusa_actuals!
      settled
    end

    # Settles several claims from one debit that paid them together (EUSA combines a payee's
    # claims into one payment), each to its share, as one unit. The row takes no claim of its own:
    # the shares are the only answer to whose spend it is. Re-checked under locks, as the screen's
    # read goes stale: the row must still need attention, two or more settleable UK claims (an
    # international claim is a payment of its own) must take shares adding up to the row's debit
    # exactly. Nothing is written otherwise; the message says why.
    def share_actual!(actual_id, shares)
      EusaActual.transaction do
        row = EusaActual.lock.find(actual_id)
        raise ShareRefusedError, "That row is already placed, so it can't be shared." unless row.shareable?
        raise ShareRefusedError, "Give two or more claims a share: one claim is a plain link." if shares.size < 2

        total = shares.sum { |share| share[:amount] }
        unless total == row.debit
          raise ShareRefusedError, "The shares come to #{money(total)}, not the row's #{money(row.debit)}."
        end

        shares.each do |share|
          expense = Expense.lock.find(share[:expense_id])
          if (reason = share_refusal(expense, row))
            raise ShareRefusedError, "##{expense.auto_number} can't take a share: it #{reason}."
          end

          ClaimShare.create!(eusa_actual: row, expense: expense, amount: share[:amount])
          attrs = { status: Status::PAID, payment_confirmed_date: row.date }
          attrs[:amount_excl_vat] = expense.amount if Reconciliation.vat_not_reclaimed?(expense, share[:amount])
          update_expense!(expense.record_id, attrs)
        end
      end
      bust_eusa_actuals!
      bust_budgets!
    end

    # The way back out of a share: the shares go, each claim returns to Submitted with no payment
    # date (as #unlink_actual_from_expense! returns one), and the row needs attention again.
    def unshare_actual!(actual_id)
      EusaActual.transaction do
        row = EusaActual.lock.find(actual_id)
        row.claim_shares.includes(:expense).each do |share|
          share.destroy!
          revert_settlement!(share.expense)
        end
      end
      bust_eusa_actuals!
      bust_budgets!
    end

    # Links a further debit to a claim another row already settled (EUSA paid it in parts). The
    # claim does not move; its budget's EUSA actual sums every part. Refused under locks when the
    # parts would come to more than the claim (Reconciliation.part_fits?), so EUSA paying twice
    # stays on the ledger to be seen.
    def add_part_payment!(actual_id, expense_id)
      EusaActual.transaction do
        row = EusaActual.lock.find(actual_id)
        expense = Expense.lock.find(expense_id)
        if (reason = part_refusal(expense, row))
          raise PartRefusedError, reason
        end

        row.update!(expense_id: expense.id)
      end
      bust_eusa_actuals!
      bust_budgets!
    end

    # Every expense a debit may settle, as a fresh array the caller may consume from: Submitted or
    # Paid, and neither linked to an imported actual, given a share of one, nor payment-confirmed.
    # Dedup only catches an identical row, so a near-duplicate would otherwise pay a claim twice.
    # Reconcile and #settle_from_matching_actual! both read it, so a save links exactly what an
    # import would.
    def matchable_expenses
      reconciled = reconciled_expense_ids
      expenses.select do |e|
        e.status.in?([ Status::SUBMITTED, Status::PAID ]) &&
          e.payment_confirmed_date.blank? && !reconciled.include?(e.record_id)
      end
    end

    # Record ids of the claims some ledger row pays: linked to one, or holding a share of one.
    def reconciled_expense_ids
      eusa_actuals.flat_map { |actual| [ actual.expense_id, *actual.claim_shares.map(&:expense_id) ] }
                  .compact.to_set(&:to_s)
    end

    # Links a claim to the one unlinked ledger row Reconcile would have matched it to had it looked
    # like this when the row was imported, and settles it; returns the row, or nil. Matching runs only
    # at import, so a claim corrected afterwards would otherwise stay unlinked for ever. Reconcile's
    # rule (Reconciliation.match_debit_to_expense over #matchable_expenses, one cost centre), plus
    # mutual best: the row must prefer this claim to every other matchable one, or the claim edited
    # second takes the row from the claim it belongs to. Two rows answering is a guess, so nil.
    def settle_from_matching_actual!(expense_id)
      matchable = matchable_expenses
      expense = matchable.find { |e| e.record_id == expense_id.to_s }
      return nil unless expense

      picks = eusa_actuals.select do |row|
        row.needs_attention? && row.debit.to_d.positive? && same_pot?(expense, row) &&
          Reconciliation.match_debit_to_expense(row, matchable.select { |e| same_pot?(e, row) }).equal?(expense)
      end
      settle_with_row!(picks.sole, expense) if picks.one?
    end

    def link_actual_to_budget!(actual_id, budget_id)
      actual = EusaActual.find(actual_id)
      actual.update!(budget_id: budget_id)
      bust_eusa_actuals!
      actual
    end

    # The ledger's "Link credits". The plan predates the click, so the row is re-checked under a
    # lock: still unplaced, no reversal since (CreditLinks' hold-back), budget still Income.
    def link_credit_to_budget!(actual_id, budget_id)
      linked = EusaActual.transaction do
        actual = EusaActual.lock.find(actual_id)
        next false unless actual.apportionable? && Budget.exists?(id: budget_id, budget_type: "Income")
        opposite = EusaActual.where(nominal_code: actual.nominal_code).includes(:allocations, :claim_shares)
                             .select { |row| row.signed_amount == -actual.signed_amount }
        next false if actual.offset_candidates(opposite).any?

        actual.update!(budget_id: budget_id)
        true
      end
      bust_eusa_actuals!
      linked
    end

    # Turns an unlinked debit row into a From-EUSA expense and links the row to it as one unit;
    # raises NotConvertibleError if the row is not (or no longer) convertible. Two writes could
    # leave a Paid expense charged to a budget while the row keeps offering "Create expense", so
    # the next click double-counts the same EUSA charge. The caller's check goes stale on a
    # double-submitted form, so it is re-taken here under a row lock: the second writer blocks,
    # then sees the link and is refused.
    def create_expense_for_actual!(actual_id, attrs)
      expense = EusaActual.transaction do
        actual = EusaActual.lock.find(actual_id)
        raise NotConvertibleError unless actual.convertible_to_expense?

        # The claim is the row's charge, so it takes the row's year, not the one active today.
        created = create_expense!(attrs.reverse_merge(financial_year: financial_year_for(actual.date)))
        link_actual_to_expense!(actual_id, created.record_id)
        created
      end
      bust_eusa_actuals!
      expense
    end

    # Imports both legs of an offsetting pair and cross-links them as one unit; returns the two
    # legs. Separate creates could commit the debit leg without the offset stamp, so every rollup
    # reads it as spend, and re-pasting cannot repair it because dedup skips the imported leg.
    def create_offsetting_pair!(debit_attrs, credit_attrs)
      legs = EusaActual.transaction do
        debit = create_actual!(debit_attrs)
        credit = create_actual!(credit_attrs)
        link_offsetting_pair!(debit.record_id, credit.record_id)
      end
      bust_eusa_actuals!
      legs
    end

    # Imports a row that paid several claims and shares it among them (#share_actual!) as one unit:
    # a row written without its shares would read as unlinked spend, and dedup would stop a re-paste.
    def create_shared_actual!(attrs, shares)
      row = EusaActual.transaction do
        created = create_actual!(attrs)
        share_actual!(created.record_id, shares)
        created
      end
      bust_eusa_actuals!
      row
    end

    # Imports the rows that paid one claim in parts as one unit: the first settles the claim, the
    # rest are further parts (#add_part_payment!).
    def create_split_payment!(rows_attrs, expense_id)
      rows = EusaActual.transaction do
        created = rows_attrs.map { |attrs| create_actual!(attrs) }
        first, *parts = created
        settle_expense_from_actual!(first.record_id, expense_id, payment_date: first.date)
        parts.each { |part| add_part_payment!(part.record_id, expense_id) }
        created
      end
      bust_eusa_actuals!
      rows
    end

    # The way back out of an offset: both legs lose the stamp and cross-link and become ordinary
    # rows. Reachable from either leg, all-or-nothing, deletes nothing. The pairing heuristic can
    # be wrong, and a wrong pair hides real spend, so this must work without a console. Any row
    # pointing at this one is cleared too, so a half-linked row from an older import is not left.
    def unlink_offsetting_pair!(actual_id)
      legs = EusaActual.transaction do
        actual = EusaActual.lock.find(actual_id)
        counterparts = EusaActual.lock.where(offset_of_id: actual.id).to_a
        counterparts << EusaActual.lock.find_by(id: actual.offset_of_id) if actual.offset_of_id
        [ actual, *counterparts ].compact.uniq.each do |leg|
          leg.update!(offset_of_id: nil, reconciliation_status: nil)
        end
      end
      bust_eusa_actuals!
      legs
    end

    # Splits one credit row across several income budgets as one unit (a Stripe payout covering
    # five shows lands on five income lines). #apportionable? refuses a row that has a budget, so
    # the allocations are the only answer to whose income it is: a row holding both would count
    # its full value on the old line and its shares on the new ones.
    #
    # The guard is re-taken under a row lock (the controller's check goes stale on a
    # double-submitted form, and a second split would double the income) and the parts must sum
    # to the row's total. One transaction, so a half-written split cannot leave the row reading as
    # unlinked while some shares already sit on budgets.
    def apportion_actual!(actual_id, allocations)
      EusaActual.transaction do
        actual = EusaActual.lock.find(actual_id)
        raise NotApportionableError unless actual.apportionable?

        total = allocations.sum { |allocation| allocation[:amount] || 0 }
        raise ApportionmentMismatchError unless total == actual.apportionable_total

        allocations.each do |allocation|
          ActualAllocation.create!(eusa_actual_id: actual.id, budget_id: allocation[:budget_id],
                                   amount: allocation[:amount])
        end
        actual.update!(reconciliation_status: EusaActual::STATUS_APPORTIONED)
      end
      bust_eusa_actuals!
      bust_budgets!
    end

    # The way back out of a split: the shares go and the row is an ordinary unlinked credit
    # again. Deletes no ledger row. The stamp is cleared only if it is STATUS_APPORTIONED, so a
    # row carrying another status (an offsetting leg) cannot be stripped by mistake.
    def remove_apportionment!(actual_id)
      EusaActual.transaction do
        actual = EusaActual.lock.find(actual_id)
        actual.allocations.destroy_all
        if actual.reconciliation_status == EusaActual::STATUS_APPORTIONED
          actual.update!(reconciliation_status: nil)
        end
      end
      bust_eusa_actuals!
      bust_budgets!
    end

    # The way back out of a wrong match to an income line: the row loses its budget. This makes
    # "Split across budgets" reachable on a reconciled payout, since #apportionable? refuses a
    # row that already carries a budget. Nothing else moves: a budget link is pure attribution.
    def unlink_actual_from_budget!(actual_id)
      actual = EusaActual.find(actual_id)
      actual.update!(budget_id: nil)
      bust_eusa_actuals!
      bust_budgets!
      actual
    end

    # The way back out of a wrong match to a claim, undoing the settlement as well as the link in
    # one transaction. #settle_expense_from_actual! wrote Paid + payment_confirmed_date, so
    # clearing the link alone would leave a Paid claim with no ledger row behind it. A claim this
    # row settled goes back to Submitted (#revert_settlement!); one that is not Paid was only
    # linked, so only the link goes, and so does one another row still pays (a part payment).
    def unlink_actual_from_expense!(actual_id)
      actual = EusaActual.transaction do
        row = EusaActual.lock.find(actual_id)
        expense = row.expense_id && Expense.lock.find_by(id: row.expense_id)
        raise ClaimFromRowError if expense&.expense_type == Expense::TYPE_FROM_EUSA

        other_parts = expense && EusaActual.where(expense_id: expense.id).where.not(id: row.id).exists?
        revert_settlement!(expense) unless other_parts
        row.update!(expense_id: nil)
        row
      end
      bust_eusa_actuals!
      bust_budgets!
      actual
    end

    # Marks two imported rows as cancelling each other (an accrual and its reversal): each is
    # stamped "offset" and pointed at the other. Both rows survive, finance needs the audit trail.
    # All-or-nothing, or one leg shows as noise and the other as real spend.
    def link_offsetting_pair!(actual_id, counterpart_id)
      legs = [ EusaActual.find(actual_id), EusaActual.find(counterpart_id) ]
      EusaActual.transaction do
        legs.each_with_index do |leg, index|
          leg.update!(offset_of_id: legs[1 - index].id,
                      reconciliation_status: EusaActual::STATUS_OFFSET)
        end
      end
      bust_eusa_actuals!
      legs
    end

    private

    def bust_eusa_actuals!
      @eusa_actuals = nil
    end

    def bust_people!
      @people = nil
    end

    def bust_batches!
      @batches = nil
    end

    def bust_budgets!
      @budgets = nil
      @budgets_for_year = nil
      @budgets_with_actuals = nil
    end

    def bust_areas!
      @areas = nil
      @areas_for_year = nil
    end

    # Swaps a line's +area_name:+ (an area this run creates) for the new row's +area_id:+. A line
    # naming an existing area already carries +area_id:+ and passes through.
    def resolve_area(attrs, areas_by_name)
      return attrs unless attrs[:area_name]

      attrs.except(:area_name).merge(area_id: resolve_area_id(attrs, areas_by_name))
    end

    def resolve_area_id(attrs, areas_by_name)
      return attrs[:area_id] if attrs[:area_name].blank?

      areas_by_name.fetch(::Reimbursements::BudgetImport.match_key(attrs[:area_name])).id
    end

    # nil when the named area was not created after all: owner syncs are grouped by the area each
    # line names, ticked re-home or not, so an area nothing lands in has no owners to write.
    # #resolve_area_id keeps its raising fetch, since a create or re-home reaching a missing area
    # is a bug.
    def resolve_optional_area_id(attrs, areas_by_name)
      return attrs[:area_id] if attrs[:area_name].blank?

      areas_by_name[::Reimbursements::BudgetImport.match_key(attrs[:area_name])]&.id
    end

    # --- Scoping -------------------------------------------------------------

    # +records+ narrowed to this store's year and cost centre; an unscoped store gets the lot.
    def scoped(records)
      in_cost_centre(in_year(records, financial_year), cost_centre)
    end

    # +records+ belonging to +year+, counting a record with NO year as belonging to it. A row can
    # be unstamped (one older than financial years, or written while no year was active), and the
    # strict reading would empty the budget list and every submitter's picker with nothing on
    # screen to say why. An unplaced row shown under the viewed year is visible and correctable;
    # hidden money is not.
    def in_year(records, year)
      return records if year.nil?

      records.select { |record| record.financial_year_id.nil? || record.financial_year_id == year.id }
    end

    # The one year whose dates hold +date+; the active year when none does, several do, or there
    # is no date.
    def financial_year_for(date)
      covering = date ? FinancialYear.covering(date, all_financial_years) : []
      covering.one? ? covering.first : all_financial_years.find(&:active?)
    end

    # Loaded once per store, as reconcile apply stamps a whole paste one row at a time.
    def all_financial_years
      @all_financial_years ||= FinancialYear.all.to_a
    end

    # The same leniency as #in_year, for cost centres (cost_centre_id is nullable on every table
    # that has it). It is a filter, so an unplaced row can appear under several centres: safe on
    # read paths only, never where money moves (see #expenses_owned_by_cost_centre).
    def in_cost_centre(records, centre)
      return records if centre.nil?

      records.select { |record| record.cost_centre_id.nil? || record.cost_centre_id == centre.id }
    end

    # Reconcile's cost-centre rule for a claim and a ledger row (ReconcileController#in_cost_centre?):
    # the same centre, and one naming none counts only while a single centre is configured.
    def same_pot?(expense, actual)
      claim_centre = expense.budget&.cost_centre_id
      return claim_centre == actual.cost_centre_id if claim_centre && actual.cost_centre_id

      @single_cost_centre = CostCentre.count == 1 unless defined?(@single_cost_centre)
      @single_cost_centre
    end

    # Settles +expense+ from +row+ under a lock on the row, which a concurrent link may have taken
    # since it was read; nil then, as when the claim itself changed (NotSettleableError).
    def settle_with_row!(row, expense)
      EusaActual.transaction do
        locked = EusaActual.lock.find(row.id)
        next nil unless locked.needs_attention?

        settle_expense_from_actual!(locked.id, expense.id, payment_date: locked.date, gbp_charged: locked.debit)
        locked
      end
    rescue NotSettleableError
      nil
    end

    # Why +expense+ cannot take a share of +row+ (completing "it …"), or nil when it can.
    def share_refusal(expense, row)
      return "is international, and EUSA pays those on their own" if expense.international?
      return if settleable?(expense, row.id)

      expense.status == Status::PAID ? "is already settled" : "is #{expense.status}"
    end

    # Why +row+ cannot be a further part of +expense+'s payment, or nil when it can.
    def part_refusal(expense, row)
      return "That row is already placed." unless row.needs_attention? && row.debit.to_d.positive?

      paid = EusaActual.where(expense_id: expense.id).to_a
      return if Reconciliation.part_fits?(expense, paid, row)

      if paid.empty? || expense.status != Status::PAID
        "##{expense.auto_number} has no payment yet, so link this row to it as its payment."
      else
        "With this row ##{expense.auto_number} would be paid more than its #{money(expense.amount)}, " \
          "so EUSA may have paid it twice."
      end
    end

    # Undoes what settling wrote: a Paid claim returns to Submitted, the status it held on reaching
    # the ledger. An international claim keeps a corrected amount: the estimate is recorded nowhere.
    def revert_settlement!(expense)
      return unless expense&.status == Status::PAID

      update_expense!(expense.record_id, status: Status::SUBMITTED, payment_confirmed_date: nil)
    end

    def money(amount) = ActiveSupport::NumberHelper.number_to_currency(amount, unit: "£")

    # Draft and Rejected never. Paid only while no payment date or other ledger row settles it: an
    # imported Paid claim with neither is still waiting for its EUSA row, and Reconcile matches it.
    # A claim with a share of a row is settled, whatever its status.
    def settleable?(expense, actual_id)
      return false if ClaimShare.exists?(expense_id: expense.id)
      return false if [ Status::DRAFT, Status::REJECTED ].include?(expense.status)
      return true unless expense.status == Status::PAID

      expense.payment_confirmed_date.blank? &&
        !EusaActual.where(expense_id: expense.id).where.not(id: actual_id).exists?
    end

    # Whether a foreign-key violation on an expense write was the budget link. MySQL names the
    # constraint, not the column, and an expense also links to a person, batch and year, so this
    # re-reads the row instead of parsing the error; any other broken link re-raises as itself.
    def budget_gone?(attrs)
      record_id = attrs[:budget_record_id]
      record_id.present? && !Budget.exists?(record_id)
    end

    # Drops nils (email-in gaps) and joins the sharepoint URL array into its newline column.
    def expense_columns(attrs)
      attrs.compact.to_h do |key, value|
        value = Array(value).join("\n") if key == :sharepoint_receipt_urls
        [ EXPENSE_KEY_MAP.fetch(key, key), value ]
      end
    end
  end
end
