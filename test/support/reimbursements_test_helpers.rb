# Builders for reimbursements tests: a fully-populated Airtable test config,
# canned Airtable record hashes, and a fake HTTP transport that records requests.
module ReimbursementsTestHelpers
  # The complete set of Airtable field ids the app code resolves through
  # +Config#fid+ (per table). This is the source of truth for "fields the app
  # needs": the schema-drift guard (schema_drift_test.rb) and the
  # +reimbursements:verify_airtable_schema+ rake task iterate it and assert each
  # one resolves against a config, so a renamed/removed Airtable column can't
  # degrade to blank data silently (fid now returns nil rather than raising).
  #
  # Keep it in sync with the code: the guard's "list stays in sync" test scans
  # the mapper/store/client source for every literal fid(:table, :field) call and
  # fails if one isn't listed here. Write-only fields that never appear as a
  # literal pair (they flow through a writer's dynamic key) are marked below.
  EXPECTED_AIRTABLE_FIELDS = {
    people: %i[name email sort_code account_number verified notes],
    budgets: %i[
      name nominal_code active budget_type initial_budget remaining owner notes
      current_forecast committed_amount total_paid variance
    ],
    budget_forecasts: %i[name budget amount date reason],
    expenses: %i[
      auto_number payee type payee_name_override sort_code_override
      account_number_override amount amount_excl_vat budget nominal_code_override
      description receipt payment_reference status rejection_reason
      producer_notified submitted_at ai_check_status ai_comment ai_checked_at
      submitted_to_eusa_date payment_confirmed_date batch receipts_offloaded
      sharepoint_receipt_urls
      rejection_notified
    ],
    batches: %i[
      name date_sent sharepoint_backup_url eusa_draft_created draft_message_id
      producer_notifications_sent notes
    ],
    eusa_actuals: %i[
      nominal_code cost_centre ref date period narrative narrative_1 debit credit
      net linked_expense linked_budget source_month imported_at
    ]
  }.freeze

  FIELD_IDS = {
    people: {
      name: "fldPplName", email: "fldPplEmail", sort_code: "fldPplSort",
      account_number: "fldPplAcct", verified: "fldPplVer", notes: "fldPplNotes"
    },
    budgets: {
      name: "fldBudName", nominal_code: "fldBudNom", active: "fldBudActive",
      initial_budget: "fldBudInit", remaining: "fldBudRem", budget_type: "fldBudType",
      owner: "fldBudOwner", notes: "fldBudNotes", current_forecast: "fldBudFcast",
      committed_amount: "fldBudCommit", total_paid: "fldBudPaid", variance: "fldBudVar",
      budget_forecasts: "fldBudFcastLink"
    },
    budget_forecasts: {
      name: "fldFcName", budget: "fldFcBudget", amount: "fldFcAmount",
      date: "fldFcDate", reason: "fldFcReason"
    },
    expenses: {
      auto_number: "fldExpNum", payee: "fldExpPayee", type: "fldExpType",
      payee_name_override: "fldExpPNO", sort_code_override: "fldExpSCO",
      account_number_override: "fldExpANO", amount: "fldExpAmt",
      amount_excl_vat: "fldExpExVat", budget: "fldExpBudget",
      nominal_code_override: "fldExpNomO", description: "fldExpDesc",
      receipt: "fldExpRcpt", payment_reference: "fldExpRef", status: "fldExpStatus",
      rejection_reason: "fldExpRej", producer_notified: "fldExpNotif",
      submitted_at: "fldExpSubAt", ai_check_status: "fldExpAiSt",
      ai_comment: "fldExpAiCom", ai_checked_at: "fldExpAiAt",
      submitted_to_eusa_date: "fldExpSubEusa", payment_confirmed_date: "fldExpPayConf",
      batch: "fldExpBatch", receipts_offloaded: "fldExpOffload",
      sharepoint_receipt_urls: "fldExpSpUrls", rejection_notified: "fldExpRejNotif"
    },
    batches: {
      name: "fldBatName", date_sent: "fldBatDate", bacs_request_file: "fldBatFile",
      sharepoint_backup_url: "fldBatSpUrl", eusa_draft_created: "fldBatDraft",
      draft_message_id: "fldBatchDraftMsgId",
      producer_notifications_sent: "fldBatNotif", notes: "fldBatNotes"
    },
    eusa_actuals: {
      name: "fldActName", nominal_code: "fldActNom", cost_centre: "fldActCC",
      ref: "fldActRef", date: "fldActDate", period: "fldActPeriod",
      narrative: "fldActNarr", narrative_1: "fldActNarr1", debit: "fldActDebit",
      credit: "fldActCredit", net: "fldActNet", linked_expense: "fldActExp",
      linked_budget: "fldActBud", source_month: "fldActMonth", imported_at: "fldActImp"
    }
  }.freeze

  # No mocking library in this suite: swap Honeybadger.notify for a recorder
  # for the duration of the block, then restore the original method.
  def capture_honeybadger_notices
    notices = []
    original = Honeybadger.method(:notify)
    Honeybadger.define_singleton_method(:notify) { |error, **opts| notices << [ error, opts ] }
    yield
    notices
  ensure
    Honeybadger.define_singleton_method(:notify, original)
  end

  # Grants the finance grid permission (:manage, :reimbursements_finance) to a
  # user via the Business Manager role — the gate for every finance operator
  # controller (Review, People, ExpenseEdits, …).
  def grant_finance_permission(user)
    role = ::Role.find_by(name: "Business Manager") || ::Role.create!(name: "Business Manager").tap do |r|
      r.permissions << Admin::Permission.create(action: "manage", subject_class: "reimbursements_finance")
    end
    user.add_role("Business Manager")
    role
  end

  # Grants the producer portal permission (:access, :reimbursements) via a
  # Producer role — used to prove that portal access alone does NOT open the
  # finance operator surfaces.
  def grant_producer_permission(user)
    role = ::Role.find_by(name: "Producer") || ::Role.create!(name: "Producer").tap do |r|
      r.permissions << Admin::Permission.create(action: "access", subject_class: "reimbursements")
    end
    user.add_role("Producer")
    role
  end

  # Assert every EXPECTED_AIRTABLE_FIELDS entry resolves (non-nil) against
  # +config+, reporting the full list of missing table/field pairs in one go so a
  # schema drift surfaces every gap at once rather than one failure per run.
  def assert_airtable_fields_resolve(config, expected: EXPECTED_AIRTABLE_FIELDS)
    missing = expected.flat_map do |table, fields|
      fields.filter_map { |field| "#{table}.#{field}" if config.fid(table, field).nil? }
    end
    assert_empty missing,
                 "Airtable schema drift: these fields the app needs did not resolve " \
                 "in the config (renamed/removed column, or credentials lag the code): " \
                 "#{missing.join(', ')}"
  end

  def reimbursements_test_config
    Reimbursements::Airtable::Config.new(
      base_id: "appTestBase",
      tables: {
        people: "tblPeople", budgets: "tblBudgets", expenses: "tblExpenses",
        batches: "tblBatches", eusa_actuals: "tblEusaActuals",
        budget_forecasts: "tblBudgetForecasts"
      },
      fields: FIELD_IDS,
      status_options: {
        draft: "Draft", pending: "Pending", approved: "Approved",
        submitted: "Submitted", paid: "Paid", rejected: "Rejected"
      }
    )
  end

  def airtable_person_record(id: "recPer1", name: "Pat Producer", email: "pat@example.com",
                             sort_code: nil, account_number: nil, verified: nil)
    f = FIELD_IDS[:people]
    fields = {
      f[:name] => name, f[:email] => email, f[:sort_code] => sort_code,
      f[:account_number] => account_number, f[:verified] => verified
    }.compact
    { "id" => id, "fields" => fields }
  end

  def airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000", active: true,
                             initial_budget: nil, budget_type: nil, remaining: nil,
                             owner_ids: nil, notes: nil, current_forecast: nil,
                             committed_amount: nil, total_paid: nil, variance: nil,
                             budget_forecast_ids: nil)
    f = FIELD_IDS[:budgets]
    fields = {
      f[:name] => name, f[:nominal_code] => nominal_code, f[:active] => active,
      f[:initial_budget] => initial_budget, f[:budget_type] => budget_type,
      f[:remaining] => remaining, f[:owner] => owner_ids, f[:notes] => notes,
      f[:current_forecast] => current_forecast, f[:committed_amount] => committed_amount,
      f[:total_paid] => total_paid, f[:variance] => variance,
      f[:budget_forecasts] => budget_forecast_ids
    }.compact
    { "id" => id, "fields" => fields }
  end

  def airtable_budget_forecast_record(id: "recFc1", **attrs)
    f = FIELD_IDS[:budget_forecasts]
    fields = {
      f[:name] => attrs.fetch(:name, "Props forecast"),
      f[:budget] => Array(attrs.fetch(:budget_id, "recBud1")),
      f[:amount] => attrs.fetch(:amount, 500.0),
      f[:date] => attrs.fetch(:date, "2026-05-01"),
      f[:reason] => attrs.fetch(:reason, "Initial projection")
    }.compact
    { "id" => id, "fields" => fields }
  end

  def airtable_expense_record(id: "recExp1", overrides: {}, **attrs)
    f = FIELD_IDS[:expenses]
    fields = {
      f[:auto_number] => attrs.fetch(:auto_number, 1),
      f[:payee] => Array(attrs.fetch(:payee_id, "recPer1")),
      f[:budget] => Array(attrs.fetch(:budget_id, "recBud1")),
      f[:amount] => attrs.fetch(:amount, 12.5),
      f[:amount_excl_vat] => attrs.fetch(:amount_excl_vat, 10.42),
      f[:description] => attrs.fetch(:description, "Fake blood"),
      f[:status] => attrs.fetch(:status, "Pending"),
      f[:payment_reference] => attrs.fetch(:payment_reference, "PROPS PAT"),
      f[:receipt] => attrs.fetch(:receipts, [
        { "id" => "att1", "filename" => "receipt.pdf", "url" => "https://airtable/signed", "size" => 1234, "type" => "application/pdf",
          "thumbnails" => { "large" => { "url" => "https://airtable/thumb-large" } } }
      ])
    }
    fields.delete_if { |_, v| v.nil? || v == [] }
    fields.merge!(overrides)
    { "id" => id, "fields" => fields }
  end

  def airtable_batch_record(id: "recBat1", **attrs)
    f = FIELD_IDS[:batches]
    fields = {
      f[:name] => attrs.fetch(:name, "BACS 2026-05-13"),
      f[:date_sent] => attrs.fetch(:date_sent, "2026-05-13"),
      f[:sharepoint_backup_url] => attrs.fetch(:sharepoint_backup_url, nil),
      f[:eusa_draft_created] => attrs.fetch(:eusa_draft_created, nil),
      f[:draft_message_id] => attrs.fetch(:draft_message_id, nil),
      f[:producer_notifications_sent] => attrs.fetch(:producer_notifications_sent, nil),
      f[:notes] => attrs.fetch(:notes, nil)
    }.compact
    { "id" => id, "fields" => fields }
  end

  def airtable_eusa_actual_record(id: "recAct1", **attrs)
    f = FIELD_IDS[:eusa_actuals]
    fields = {
      f[:nominal_code] => attrs.fetch(:nominal_code, "439999"),
      f[:cost_centre] => attrs.fetch(:cost_centre, "F40"),
      f[:period] => attrs.fetch(:period, nil),
      f[:narrative] => attrs.fetch(:narrative, "Alice Producer"),
      f[:date] => attrs.fetch(:date, "2026-05-13"),
      f[:debit] => attrs.fetch(:debit, 123.45),
      f[:credit] => attrs.fetch(:credit, nil),
      f[:linked_expense] => attrs.fetch(:linked_expense, nil),
      f[:linked_budget] => attrs.fetch(:linked_budget, nil),
      f[:imported_at] => attrs.fetch(:imported_at, nil),
      f[:source_month] => attrs.fetch(:source_month, "2026-05")
    }.compact
    { "id" => id, "fields" => fields }
  end

  # Fake Airtable client counting calls per table, interface-compatible with
  # Reimbursements::Airtable::Client. Records writes for assertions.
  class FakeAirtableClient
    attr_reader :list_calls, :get_calls, :created, :updated, :uploads, :deleted
    attr_accessor :fail_uploads
    # Make every create_record for these tables raise, standing in for an
    # Airtable write outage (e.g. the Batch-record write failing after the EUSA
    # draft was already created — the orphan-draft path).
    attr_accessor :fail_create_tables
    # Make every update_record for these tables raise, standing in for an
    # Airtable write outage on an existing record (e.g. mark_submitted's
    # per-expense status write failing after the EUSA draft already exists).
    attr_accessor :fail_update_tables
    # Make every get_record for these tables raise a non-404 Error, standing
    # in for a genuine Airtable outage on a single-record fetch — the real
    # client only swallows a 404; anything else re-raises, which this fake
    # otherwise can't reproduce (it just returns nil on any non-match).
    attr_accessor :fail_get_tables

    def initialize(records_by_table)
      @records_by_table = records_by_table
      @list_calls = Hash.new(0)
      @get_calls = []
      @created = []
      @updated = []
      @uploads = []
      @deleted = []
      @fail_create_tables = []
      @fail_update_tables = []
      @fail_get_tables = []
    end

    def list_records(table)
      @list_calls[table] += 1
      @records_by_table.fetch(table, [])
    end

    def get_record(table, record_id)
      @get_calls << [ table, record_id ]
      if Array(@fail_get_tables).include?(table)
        raise Reimbursements::Airtable::Error.new("get failed for #{table}", status: 500)
      end

      @records_by_table.fetch(table, []).find { |r| r["id"] == record_id }
    end

    def create_record(table, fields)
      if Array(@fail_create_tables).include?(table)
        raise Reimbursements::Airtable::Error.new("create failed for #{table}", status: 500)
      end

      @created << [ table, fields ]
      { "id" => "recNew#{@created.size}", "fields" => fields }
    end

    def update_record(table, record_id, fields)
      if Array(@fail_update_tables).include?(table)
        raise Reimbursements::Airtable::Error.new("update failed for #{table}", status: 500)
      end

      @updated << [ table, record_id, fields ]
      record = @records_by_table.fetch(table, []).find { |r| r["id"] == record_id }
      record["fields"] = record["fields"].merge(fields) if record
      record || { "id" => record_id, "fields" => fields }
    end

    def upload_attachment(record_id, **kwargs)
      raise Reimbursements::Airtable::Error.new("upload failed", status: 500) if fail_uploads

      @uploads << [ record_id, kwargs ]
      { "id" => record_id }
    end

    def delete_record(table, record_id)
      @deleted << [ table, record_id ]
      @records_by_table.fetch(table, []).reject! { |r| r["id"] == record_id }
      { "id" => record_id, "deleted" => true }
    end
  end

  # Builds a Store on a FakeAirtableClient + MemoryStore cache. Returns [store, client].
  def build_fake_store(expenses: [], people: [], budgets: [], eusa_actuals: [], batches: [],
                       budget_forecasts: [])
    client = FakeAirtableClient.new(expenses: expenses, people: people, budgets: budgets,
                                    eusa_actuals: eusa_actuals, batches: batches,
                                    budget_forecasts: budget_forecasts)
    store = Reimbursements::Store.new(client: client, config: reimbursements_test_config,
                                      cache: ActiveSupport::Cache::MemoryStore.new)
    [ store, client ]
  end

  # Overrides +client+'s update_record to raise for calls matching the given
  # predicate, otherwise performing the client's normal write-through — the
  # shared body for tests that need one specific write to fail amid others
  # that must still succeed.
  def fail_update_record_when(client, &predicate)
    client.define_singleton_method(:update_record) do |table, record_id, fields|
      raise Reimbursements::Airtable::Error.new("blip", status: 500) if predicate.call(table, record_id, fields)

      super(table, record_id, fields)
    end
  end

  # Fake RubyLLM chat for the Gemini call sites (Extractor, AiChecker): records
  # the schema, prompt and attachments it was asked with, then returns a canned
  # structured response (or raises). Mirrors the fluent
  # RubyLLM.chat.with_schema(...).ask(...) chain.
  class FakeChat
    Response = Struct.new(:content)
    attr_reader :schema, :prompt, :attachments

    def initialize(content: nil, error: nil)
      @content = content
      @error = error
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def ask(prompt, with: nil)
      @prompt = prompt
      @attachments = with
      raise @error if @error

      Response.new(@content)
    end
  end

  # Stand-in for BatchProcessor in the job tests (nightly + interactive build):
  # records each process(**kwargs) call and returns a canned Result.
  # +success: false+ drives the failure path.
  class FakeBatchProcessor
    Result = Struct.new(:success, :eusa_draft_web_link, :total_amount, :bacs_date, :errors,
                        :batch_id, keyword_init: true)
    attr_reader :calls

    def initialize(success: true, errors: [])
      @success = success
      @errors = errors
      @calls = []
    end

    def process(**kwargs)
      @calls << kwargs
      Result.new(success: @success, eusa_draft_web_link: "https://outlook.example/draft-1",
                 total_amount: kwargs[:expenses].sum { |e| e.amount || 0 },
                 bacs_date: kwargs[:bacs_date], errors: @errors,
                 batch_id: @success ? "recBat1" : nil)
    end
  end

  # Records the operator alerts the job sends through the Graph notifier, plus
  # the mailbox it was built for — a shared stand-in for Notifier across
  # NightlyBatchJob/BuildBatchJob tests. +fail+ makes every send raise
  # +fail_with+ (a plain Graph outage by default; pass
  # Reimbursements::GraphAuth::AuthError to drive the IT-escalation path).
  class FakeNotifier
    attr_reader :calls, :mailbox

    def initialize(mailbox: nil, fail: false, fail_with: Reimbursements::GraphAuth::Error)
      @mailbox = mailbox
      @fail = fail
      @fail_with = fail_with
      @calls = []
    end

    def record(name, kwargs)
      raise @fail_with, "graph down" if @fail

      @calls << [ name, kwargs ]
      nil
    end

    def pending_reminder(**k) = record(:pending_reminder, k)
    def manual_review(**k) = record(:manual_review, k)
    def approved_ready(**k) = record(:approved_ready, k)
    def batch_ready(**k) = record(:batch_ready, k)
    def failure(**k) = record(:failure, k)
  end

  # Fake GraphClient for BatchProcessor / Build Batch / Notifier tests: records
  # drafts, sent mail, uploads and downloads, with toggles to make the draft,
  # a send, or uploads fail.
  class FakeGraphClient
    attr_reader :uploaded, :drafts, :downloads, :send_mails, :deleted_messages
    attr_accessor :fail_draft, :fail_uploads, :fail_send, :fail_delete_message, :fail_download
    # Recipients (email strings) whose send should raise, standing in for a
    # Graph outage that hits some payees but not others.
    attr_accessor :fail_send_to
    # Filenames whose upload_to_folder call should raise, standing in for one
    # receipt failing to back up to SharePoint while the rest of the batch
    # (including other receipts and the BACS xlsx itself) succeeds.
    attr_accessor :fail_upload_for
    # What draft_message? reports — true (the common case: still an unsent
    # draft) by default; set false to simulate a draft that was already sent,
    # deleted, or otherwise couldn't be confirmed.
    attr_accessor :draft_still_exists

    def initialize
      @uploaded = []
      @drafts = []
      @downloads = []
      @send_mails = []
      @deleted_messages = []
      @fail_send_to = []
      @fail_upload_for = []
      @draft_still_exists = true
    end

    def draft_message?(mailbox:, message_id:)
      @draft_still_exists
    end

    def download(url)
      raise Reimbursements::GraphAuth::Error, "receipt download failed for #{url}" if fail_download

      @downloads << url
      "BYTES(#{url})"
    end

    def upload_to_folder(drive_id:, folder_id:, filename:, content:)
      raise Reimbursements::GraphAuth::Error, "SharePoint down" if fail_uploads
      raise Reimbursements::GraphAuth::Error, "SharePoint down for #{filename}" if Array(fail_upload_for).include?(filename)

      @uploaded << { drive_id: drive_id, folder_id: folder_id, filename: filename, size: content.bytesize }
      "https://sp.example/#{folder_id}/#{filename}"
    end

    def create_draft(mailbox:, to:, subject:, html:, attachments:)
      raise Reimbursements::GraphAuth::Error, "draft failed" if fail_draft

      @drafts << { mailbox: mailbox, to: to, subject: subject, html: html,
                   attachments: attachments.map(&:filename) }
      Reimbursements::GraphClient::Draft.new(id: "msg-#{@drafts.size}",
                                             web_link: "https://outlook.example/draft-1")
    end

    def delete_message(mailbox:, message_id:)
      raise Reimbursements::GraphAuth::Error, "delete failed" if fail_delete_message

      @deleted_messages << { mailbox: mailbox, message_id: message_id }
      nil
    end

    def send_mail(mailbox:, to:, subject:, html:)
      raise Reimbursements::GraphAuth::Error, "send failed" if fail_send
      if (Array(to) & Array(fail_send_to)).any?
        raise Reimbursements::GraphAuth::Error, "send failed for #{to.inspect}"
      end

      @send_mails << { mailbox: mailbox, to: to, subject: subject, html: html }
      nil
    end
  end

  # Fake transport compatible with the reimbursements HTTP clients:
  # responds with queued [status, body] pairs and records every request.
  class FakeHttp
    Request = Struct.new(:method, :uri, :headers, :body)

    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def call(http_method, uri, headers, body)
      @requests << Request.new(http_method, uri.to_s, headers, body)
      response = @responses.shift || raise("FakeHttp exhausted after #{@requests.size} requests")
      # A queued Exception simulates a transport-level failure (timeout, DNS,
      # TLS) rather than an ordinary HTTP response.
      raise response if response.is_a?(Exception)

      response
    end
  end
end
