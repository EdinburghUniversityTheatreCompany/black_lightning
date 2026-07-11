# Builders for reimbursements tests: a fully-populated Airtable test config,
# canned Airtable record hashes, and a fake HTTP transport that records requests.
module ReimbursementsTestHelpers
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
      f[:narrative] => attrs.fetch(:narrative, "Alice Producer"),
      f[:date] => attrs.fetch(:date, "2026-05-13"),
      f[:debit] => attrs.fetch(:debit, 123.45),
      f[:credit] => attrs.fetch(:credit, nil),
      f[:linked_expense] => attrs.fetch(:linked_expense, nil),
      f[:source_month] => attrs.fetch(:source_month, "2026-05")
    }.compact
    { "id" => id, "fields" => fields }
  end

  # Fake Airtable client counting calls per table, interface-compatible with
  # Reimbursements::Airtable::Client. Records writes for assertions.
  class FakeAirtableClient
    attr_reader :list_calls, :get_calls, :created, :updated, :uploads, :deleted
    attr_accessor :fail_uploads

    def initialize(records_by_table)
      @records_by_table = records_by_table
      @list_calls = Hash.new(0)
      @get_calls = []
      @created = []
      @updated = []
      @uploads = []
      @deleted = []
    end

    def list_records(table)
      @list_calls[table] += 1
      @records_by_table.fetch(table, [])
    end

    def get_record(table, record_id)
      @get_calls << [ table, record_id ]
      @records_by_table.fetch(table, []).find { |r| r["id"] == record_id }
    end

    def create_record(table, fields)
      @created << [ table, fields ]
      { "id" => "recNew#{@created.size}", "fields" => fields }
    end

    def update_record(table, record_id, fields)
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

  # Fake GraphClient for BatchProcessor / Build Batch tests: records drafts,
  # uploads and downloads, with toggles to make the draft or uploads fail.
  class FakeGraphClient
    attr_reader :uploaded, :drafts, :downloads
    attr_accessor :fail_draft, :fail_uploads

    def initialize
      @uploaded = []
      @drafts = []
      @downloads = []
    end

    def download(url)
      @downloads << url
      "BYTES(#{url})"
    end

    def upload_to_folder(drive_id:, folder_id:, filename:, content:)
      raise Reimbursements::GraphAuth::Error, "SharePoint down" if fail_uploads

      @uploaded << { drive_id: drive_id, folder_id: folder_id, filename: filename, size: content.bytesize }
      "https://sp.example/#{folder_id}/#{filename}"
    end

    def create_draft(mailbox:, to:, subject:, html:, attachments:)
      raise Reimbursements::GraphAuth::Error, "draft failed" if fail_draft

      @drafts << { mailbox: mailbox, to: to, subject: subject, html: html,
                   attachments: attachments.map(&:filename) }
      "https://outlook.example/draft-1"
    end
  end

  FakeMailerDelivery = Struct.new(:noop) do
    def deliver_later = nil
  end

  # Fake BatchMailer capturing producer_notification calls.
  class FakeBatchMailer
    attr_reader :sent

    def initialize
      @sent = []
    end

    def producer_notification(**kwargs)
      @sent << kwargs
      FakeMailerDelivery.new
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
      @responses.shift || raise("FakeHttp exhausted after #{@requests.size} requests")
    end
  end
end
