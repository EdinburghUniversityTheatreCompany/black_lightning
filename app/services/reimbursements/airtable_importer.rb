module Reimbursements
  ##
  # One-shot, idempotent, re-runnable backfill from Airtable into the
  # reimbursements_* MySQL tables (Phase H cutover, step 2). Reads every
  # record through the Airtable-backed Store (so it costs one list call per
  # table, cache-fronted) and upserts AR rows keyed by airtable_record_id —
  # safe to run repeatedly while Airtable stays live, then one final time
  # just before flipping REIMBURSEMENTS_BACKEND.
  #
  # Beyond the design doc's tables, this also:
  # - streams each Airtable receipt into ActiveStorage (their signed URLs
  #   expire ~2h, so download happens in the same pass);
  # - imports budget forecasts and budget->owner links;
  # - stamps every budget/expense/actual with the financial year and every
  #   budget with the default cost centre;
  # - REMAPS the MySQL-native tables that key on Airtable string record ids
  #   (owner_endorsements, batch_attempts, users.airtable_person_id ->
  #   users.reimbursements_person_id) onto the new numeric ids.
  #
  # Fails loudly: verify! checks row counts, an amount+status checksum and
  # receipt presence before the flip is allowed.
  class AirtableImporter
    class ImportError < StandardError; end

    DEFAULT_YEAR_LABEL = "Fringe 2026".freeze

    def initialize(store: Store.new, transport: HttpTransport, io: $stdout,
                   financial_year_label: DEFAULT_YEAR_LABEL)
      @store = store # must be the Airtable-backed store at import time
      @transport = transport
      @io = io
      @financial_year_label = financial_year_label
    end

    def import!
      guard_duplicate_person_emails!
      @year = FinancialYear.find_or_create_by!(label: @financial_year_label) do |y|
        y.active = true unless FinancialYear.active.exists?
      end

      import_people
      import_budgets
      import_budget_forecasts
      import_batches
      import_expenses
      import_eusa_actuals
      backfill_users
      remap_owner_endorsements
      remap_batch_attempts
      verify!
      @io.puts "Import verified."
    end

    private

    # A duplicate email in the Airtable People table would trip the new
    # unique index mid-import; surface all of them up front so they can be
    # merged in Airtable first.
    def guard_duplicate_person_emails!
      dupes = @store.people.filter_map { |p| p.email.to_s.strip.downcase.presence }
                    .tally.select { |_, n| n > 1 }.keys
      return if dupes.empty?

      raise ImportError, "Duplicate People emails in Airtable (merge before importing): #{dupes.join(', ')}"
    end

    def import_people
      @store.people.each do |p|
        row = Person.find_or_initialize_by(airtable_record_id: p.record_id)
        row.assign_attributes(name: p.name, email: p.email)
        row.save!
        import_payment_details(row, p)
      end
      @io.puts "People: #{Person.count}"
    end

    # Bank details on the Airtable People record become the linked
    # PaymentDetails row — only when the payee actually has any.
    def import_payment_details(row, p)
      return unless p.sort_code.present? || p.account_number.present? ||
                    p.verified || p.notes.present?

      details = PaymentDetails.find_or_initialize_by(person_id: row.id)
      details.update!(sort_code: p.sort_code.to_s, account_number: p.account_number.to_s,
                      verified: p.verified, notes: p.notes)
    end

    def import_budgets
      cost_centre = CostCentre.default
      @store.budgets.each do |b|
        row = Budget.find_or_initialize_by(airtable_record_id: b.record_id)
        row.update!(name: b.name, nominal_code: b.nominal_code, active: b.active,
                    budget_type: b.budget_type, initial_budget: b.initial_budget,
                    notes: b.notes, cost_centre: cost_centre, financial_year: @year)
        sync_budget_owners(row, b.owner_ids)
      end
      @io.puts "Budgets: #{Budget.count}"
    end

    def sync_budget_owners(row, airtable_owner_ids)
      owner_ids = airtable_owner_ids.map do |record_id|
        person_ids.fetch(record_id) { raise ImportError, "Budget #{row.name}: unknown owner #{record_id}" }
      end
      row.budget_ownerships.where.not(person_id: owner_ids).destroy_all
      (owner_ids - row.budget_ownerships.pluck(:person_id)).each do |person_id|
        row.budget_ownerships.create!(person_id: person_id)
      end
    end

    def import_budget_forecasts
      @store.budgets.each do |b|
        @store.budget_forecasts(b.record_id).each do |f|
          row = BudgetForecast.find_or_initialize_by(airtable_record_id: f.record_id)
          row.update!(budget_id: budget_ids.fetch(b.record_id), amount: f.amount,
                      date: f.date, reason: f.reason)
        end
      end
      @io.puts "Budget forecasts: #{BudgetForecast.count}"
    end

    def import_batches
      @store.batches.each do |b|
        row = Batch.find_or_initialize_by(airtable_record_id: b.record_id)
        row.update!(name: b.name, date_sent: b.date_sent,
                    sharepoint_backup_url: b.sharepoint_backup_url,
                    draft_message_id: b.draft_message_id.presence,
                    producer_notifications_sent: b.producer_notifications_sent,
                    notes: b.notes)
      end
      @io.puts "Batches: #{Batch.count}"
    end

    def import_expenses
      @store.expenses.each do |e|
        row = Expense.find_or_initialize_by(airtable_record_id: e.record_id)
        row.update!(
          auto_number: e.auto_number,
          person_id: e.person && person_ids.fetch(e.person.record_id),
          budget_id: e.budget && budget_ids.fetch(e.budget.record_id),
          batch_id: e.batch_id && batch_ids.fetch(e.batch_id),
          financial_year: @year,
          amount: e.amount, amount_excl_vat: e.amount_excl_vat,
          description: e.description, status: e.status, expense_type: e.expense_type,
          payee_name_override: e.payee_name_override, sort_code_override: e.sort_code_override,
          account_number_override: e.account_number_override,
          nominal_code_override: e.nominal_code_override,
          payment_reference: e.payment_reference, rejection_reason: e.rejection_reason,
          submitted_at: e.submitted_at, submitted_to_eusa_date: e.submitted_to_eusa_date,
          payment_confirmed_date: e.payment_confirmed_date,
          producer_notified: e.producer_notified, receipts_offloaded: e.receipts_offloaded,
          sharepoint_receipt_urls: Array(e.sharepoint_receipt_urls).join("\n"),
          ai_check_status: e.ai_check_status, ai_comment: e.ai_comment,
          ai_checked_at: e.ai_checked_at, rejection_notified: e.rejection_notified
        )
        import_receipts(row, e)
      end
      @io.puts "Expenses: #{Expense.count}"
    end

    # Streams each Airtable attachment into ActiveStorage. Re-runs skip files
    # already attached (matched by filename + byte size). Airtable's signed
    # URLs expire ~2h after fetch, which the Store's list TTL stays inside.
    def import_receipts(row, e)
      e.receipts.each do |receipt|
        already = row.receipt_files.any? do |file|
          file.filename.to_s == receipt.filename && file.byte_size == receipt.size_bytes
        end
        next if already

        status, body, = @transport.call(:get, URI.parse(receipt.url), {}, nil)
        raise ImportError, "Receipt download failed (#{status}) for expense #{e.record_id} #{receipt.filename}" unless status == 200

        row.receipt_files.attach(io: StringIO.new(body), filename: receipt.filename,
                                 content_type: receipt.content_type.presence || "application/octet-stream")
      end
    end

    def import_eusa_actuals
      expense_ids = Expense.where.not(airtable_record_id: nil).pluck(:airtable_record_id, :id).to_h
      @store.eusa_actuals.each do |a|
        row = EusaActual.find_or_initialize_by(airtable_record_id: a.record_id)
        row.update!(nominal_code: a.nominal_code, cost_centre: a.cost_centre, ref: a.ref,
                    date: a.date, period: a.period, narrative: a.narrative,
                    narrative_1: a.narrative_1, debit: a.debit, credit: a.credit, net: a.net,
                    source_month: a.source_month, imported_at: a.imported_at,
                    financial_year: @year,
                    expense_id: a.linked_expense_ids.first&.then { |rid| expense_ids.fetch(rid) },
                    budget_id: a.linked_budget_ids.first&.then { |rid| budget_ids.fetch(rid) })
      end
      @io.puts "EUSA actuals: #{EusaActual.count}"
    end

    # users.airtable_person_id (cached Airtable string) -> the real FK. A
    # stale id pointing at a deleted Person is cleared with a warning rather
    # than aborting the import.
    def backfill_users
      User.where.not(airtable_person_id: [ nil, "" ]).find_each do |user|
        person_id = person_ids[user.airtable_person_id]
        @io.puts "WARN: user #{user.id} airtable_person_id #{user.airtable_person_id} has no Person; clearing" if person_id.nil?
        user.update_columns(reimbursements_person_id: person_id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    # OwnerEndorsement rows key on Airtable string ids; after the flip,
    # record_id is the numeric AR id, so existing rows must be rewritten to
    # keep the endorsement gate satisfied. Idempotent: a row whose ids no
    # longer look like Airtable ids ("rec...") is already remapped.
    def remap_owner_endorsements
      OwnerEndorsement.find_each do |endorsement|
        updates = {}
        remap_value(endorsement.expense_record_id, expense_record_ids) { |v| updates[:expense_record_id] = v }
        remap_value(endorsement.budget_record_id, budget_ids) { |v| updates[:budget_record_id] = v.to_s }
        remap_value(endorsement.endorsed_by_person_id, person_ids) { |v| updates[:endorsed_by_person_id] = v.to_s }
        endorsement.update_columns(updates) if updates.any? # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def remap_batch_attempts
      BatchAttempt.where.not(batch_record_id: [ nil, "" ]).find_each do |attempt|
        remap_value(attempt.batch_record_id, batch_ids) do |v|
          attempt.update_columns(batch_record_id: v.to_s) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end

    # Yields the mapped id for an Airtable-looking record id; raises on an
    # Airtable id the import didn't see (a dangling reference must be fixed,
    # not silently dropped). Non-Airtable values (numeric or blank) pass.
    def remap_value(value, map)
      return unless value.to_s.start_with?("rec")

      mapped = map[value]
      raise ImportError, "No imported row for Airtable id #{value}" if mapped.nil?

      yield mapped
    end

    def expense_record_ids
      @expense_record_ids ||= Expense.where.not(airtable_record_id: nil)
                                     .pluck(:airtable_record_id, :id)
                                     .to_h.transform_values(&:to_s)
    end

    def person_ids
      @person_ids ||= Person.where.not(airtable_record_id: nil).pluck(:airtable_record_id, :id).to_h
    end

    def budget_ids
      @budget_ids ||= Budget.where.not(airtable_record_id: nil).pluck(:airtable_record_id, :id).to_h
    end

    def batch_ids
      @batch_ids ||= Batch.where.not(airtable_record_id: nil).pluck(:airtable_record_id, :id).to_h
    end

    # Row counts, an expenses amount+status checksum and receipt presence
    # must all match before the flip.
    def verify!
      check(:people, @store.people.size, Person.where.not(airtable_record_id: nil).count)
      check(:budgets, @store.budgets.size, Budget.where.not(airtable_record_id: nil).count)
      check(:batches, @store.batches.size, Batch.where.not(airtable_record_id: nil).count)
      check(:expenses, @store.expenses.size, Expense.where.not(airtable_record_id: nil).count)
      check(:eusa_actuals, @store.eusa_actuals.size, EusaActual.where.not(airtable_record_id: nil).count)

      air = checksum(@store.expenses.map { |e| [ e.record_id, e.amount, e.status ] })
      db = checksum(Expense.where.not(airtable_record_id: nil).pluck(:airtable_record_id, :amount, :status))
      raise ImportError, "expense amount/status checksum mismatch" unless air == db

      @store.expenses.each do |e|
        next if e.receipts.empty?

        attached = Expense.find_by!(airtable_record_id: e.record_id).receipt_files.count
        raise ImportError, "expense #{e.record_id}: #{e.receipts.size} receipts in Airtable, #{attached} attached" if attached < e.receipts.size
      end
    end

    def check(name, expected, actual)
      raise ImportError, "#{name} count mismatch: Airtable #{expected} vs DB #{actual}" unless expected == actual
    end

    # Amounts are normalised to 2dp strings — BigDecimal#to_s is scientific
    # notation and trailing-zero-sensitive, which would false-negative.
    def checksum(rows)
      normalised = rows.map do |row|
        row.map { |v| v.is_a?(Numeric) ? format("%.2f", v) : v.to_s }.join("|")
      end
      Digest::SHA256.hexdigest(normalised.sort.join("\n"))
    end
  end
end
