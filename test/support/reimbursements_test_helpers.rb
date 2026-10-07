# Seed builders and fake external services (Graph, modulus checker) for reimbursements tests.
module ReimbursementsTestHelpers
  # So tests call capture_honeybadger_notices unqualified.
  include HoneybadgerTestHelpers

  # --- Database seed helpers -----------------------------------------------

  def create_reimbursements_person(name: "Pat Producer", email: "pat@example.com",
                                   sort_code: nil, account_number: nil, verified: false,
                                   notes: nil)
    person = Reimbursements::Person.create!(name: name, email: email)
    if sort_code.present? || account_number.present? || verified || notes.present?
      person.create_payment_details!(sort_code: sort_code.to_s, account_number: account_number.to_s,
                                     verified: verified, notes: notes)
    end
    person
  end

  # notification_email is required, so it defaults to a per-key .invalid address: valid,
  # distinct per centre, and not a real-looking mailbox.
  def create_reimbursements_cost_centre(key:, name:, eusa_code:,
                                        receive_mailbox: "in@example.com",
                                        send_mailbox: "out@example.com",
                                        notification_email: nil, **attrs)
    Reimbursements::CostCentre.create!(key: key, name: name, eusa_code: eusa_code,
                                       receive_mailbox: receive_mailbox,
                                       send_mailbox: send_mailbox,
                                       notification_email: notification_email ||
                                         "#{key}-finance@example.invalid",
                                       **attrs)
  end

  # The SECOND cost centre, never a fixture: a second row makes CostCentre.default resolve
  # to whichever label FixtureSet.identify hashes lower, and deletes the one-centre world
  # the reconcile tests pin. Every two-centre test builds it here.
  def create_second_reimbursements_cost_centre(key: "termtime", name: "Bedlam Termtime",
                                               eusa_code: "BED", **attrs)
    create_reimbursements_cost_centre(key: key, name: name, eusa_code: eusa_code,
                                      receive_mailbox: "in@bedlamtheatre.invalid",
                                      send_mailbox: "out@bedlamtheatre.invalid", **attrs)
  end

  def create_reimbursements_budget(name: "Props", nominal_code: "4000", owners: [], **attrs)
    budget = Reimbursements::Budget.create!(name: name, nominal_code: nominal_code, **attrs)
    Array(owners).each { |person| budget.own_owners << person }
    budget
  end

  def create_reimbursements_area(name:, cost_centre: nil, financial_year: nil, **attrs)
    Reimbursements::Area.create!(
      name: name,
      cost_centre: cost_centre,
      financial_year: financial_year || Reimbursements::FinancialYear.current,
      **attrs
    )
  end

  # cost_centre: nil resolves through CostCentre.default, which is order(:id).first once a
  # second centre exists: pass it explicitly in any two-centre test.
  #
  # label: nil derives "Label for #{code}", not a fixed default: two codes would share it,
  # and a label assertion would pass on the wrong code or a hardcoded string.
  def create_reimbursements_nominal_code(code:, cost_centre: nil, label: nil, active: true)
    Reimbursements::NominalCode.create!(code: code, label: label || "Label for #{code}", active: active,
                                        cost_centre: cost_centre || Reimbursements::CostCentre.default)
  end

  def create_reimbursements_expense(status: Reimbursements::Status::PENDING,
                                    amount: BigDecimal("12.5"),
                                    amount_excl_vat: BigDecimal("10.42"),
                                    description: "Fake blood",
                                    payment_reference: "PROPS PAT",
                                    receipt: true, **attrs)
    expense = Reimbursements::Expense.create!(
      status: status, amount: amount, amount_excl_vat: amount_excl_vat,
      description: description, payment_reference: payment_reference, **attrs
    )
    attach_test_receipt(expense) if receipt
    expense
  end

  def attach_test_receipt(expense, filename: "receipt.pdf",
                          content_type: "application/pdf", bytes: "%PDF-1.4 test")
    expense.receipt_files.attach(io: StringIO.new(bytes), filename: filename,
                                 content_type: content_type)
    expense
  end

  # A one-sheet .xlsx holding +rows+, as an upload: the importers read only its #path, so it
  # serves a model test and a posted file alike.
  def xlsx_upload(rows, sheet: "Sheet1")
    require "caxlsx"
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: sheet) { |worksheet| rows.each { |row| worksheet.add_row row } }
    file = Tempfile.new([ "upload", ".xlsx" ])
    file.binmode
    file.write(package.to_stream.read)
    file.rewind
    (@xlsx_tempfiles ||= []) << file # a collected Tempfile deletes its file
    Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
  end

  def create_reimbursements_batch(date_sent: Date.new(2026, 5, 13), **attrs)
    Reimbursements::Batch.create!(date_sent: date_sent, **attrs)
  end

  # The header row of EUSA's ledger export, as pasted into Reconcile.
  ACTUALS_HEADER = "Nominal\tCost Centre\tRef\tDate\tPeriod\tNarrative\tNarrative 1\tDebit\tCredit\tNet".freeze

  def create_reimbursements_actual(nominal_code: "439999", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"), **attrs)
    Reimbursements::EusaActual.create!(nominal_code: nominal_code, narrative: narrative,
                                       debit: debit, **attrs)
  end

  # A fuller ledger row than the debit-only create_reimbursements_actual: it stamps the
  # columns an imported row carries and takes a +credit:+. +net+ is derived from debit and
  # credit, as EusaActual.net derives it, so a test cannot seed a second source of truth.
  def create_reimbursements_eusa_actual(nominal_code: "4100", narrative: "Stripe payout",
                                        debit: nil, credit: nil, date: Date.current,
                                        period: "06", source_month: "2026-09", **attrs)
    Reimbursements::EusaActual.create!(
      nominal_code: nominal_code, narrative: narrative, debit: debit, credit: credit,
      net: (debit || 0) - (credit || 0), date: date, period: period,
      source_month: source_month, **attrs
    )
  end

  # --- Query counting ------------------------------------------------------

  # Counts the SQL a block issues, for the preload assertions. Schema queries are
  # excluded: whichever test runs first absorbs them (45 queries against 31 for the same
  # scenario), which makes size comparisons noise.
  def count_queries(&block)
    count = 0
    callback = lambda do |*, payload|
      next if payload[:name] == "SCHEMA"
      next if payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      count += 1
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    count
  end

  # --- Assertions ----------------------------------------------------------

  # A finance list's "Download CSV": text/csv named reimbursements-<resource>-<today>.csv.
  def assert_csv_download(slug)
    assert_response :success
    assert_includes response.media_type, "text/csv"
    disposition = response.headers["Content-Disposition"]
    assert_match(/attachment/, disposition)
    assert_match(/reimbursements-#{slug}-\d{4}-\d{2}-\d{2}\.csv/, disposition)
  end

  # Grants :manage, :reimbursements_finance through the Business Manager role.
  def grant_finance_permission(user)
    grant_role_permission(user, "Business Manager", "manage", "reimbursements_finance")
  end

  # Grants :access, :reimbursements through a Producer role, to prove portal access alone
  # does not open the finance surfaces.
  def grant_producer_permission(user)
    grant_role_permission(user, "Producer", "access", "reimbursements")
  end

  # --- Graph plumbing -------------------------------------------------------

  # Delegates outbound_enabled? to the real Settings, so a suppression test can delete the
  # REIMBURSEMENTS_ENABLE_OUTBOUND opt-in the suite sets.
  FakeGraphSettings = Struct.new(:azure_tenant_id, :azure_client_id, :azure_client_secret) do
    def outbound_enabled?
      Reimbursements::Settings.outbound_enabled?
    end
  end

  # The real Graph body for a message handled or deleted by hand in Outlook.
  GRAPH_ITEM_NOT_FOUND = { error: { code: "ErrorItemNotFound",
                                    message: "The specified object was not found in the store." } }.to_json

  def graph_settings
    FakeGraphSettings.new("tenant-1", "client-1", "secret-1")
  end

  def graph_token_response(expires_in: 3600)
    [ 200, { access_token: "tok-1", expires_in: expires_in }.to_json ]
  end

  # Runs the block with the suite's outbound opt-in switched off.
  def without_outbound
    original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
    yield
  ensure
    ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
  end

  # Modulus verdict keyed by account number.
  class FakeModulusChecker
    def initialize(by_account = {})
      @by_account = by_account
    end

    # A blank pair reads INVALID, as the real checker does.
    def check(sort_code, account_number)
      if sort_code.to_s.strip.empty? || account_number.to_s.strip.empty?
        return ::Reimbursements::ModulusCheck::INVALID
      end

      @by_account.fetch(account_number, ::Reimbursements::ModulusCheck::OUTSIDE_SPEC)
    end
  end

  # Stand-in for BatchProcessor in BuildBatchJob tests: records each process call and
  # returns a canned Result. +success: false+ drives the failure path.
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

  # Stand-in for Notifier in NightlyBatchJob/BuildBatchJob tests: records each alert and
  # the mailbox it was built for. +fail+ makes every send raise +fail_with+ (pass
  # ::GraphAuth::AuthError for the IT-escalation path); +fail_only+ fails just the named
  # alerts, which is how the nightly's partly-failed-run recording is proved.
  class FakeNotifier
    attr_reader :calls, :mailbox

    def initialize(mailbox: nil, fail: false, fail_only: [],
                   fail_with: ::GraphAuth::Error)
      @mailbox = mailbox
      @fail = fail
      @fail_only = Array(fail_only)
      @fail_with = fail_with
      @calls = []
    end

    def record(name, kwargs)
      raise @fail_with, "graph down" if @fail || @fail_only.include?(name)

      @calls << [ name, kwargs ]
      nil
    end

    def pending_reminder(**k) = record(:pending_reminder, k)
    def owner_sign_off_reminder(**k) = record(:owner_sign_off_reminder, k)
    def approved_ready(**k) = record(:approved_ready, k)
    def batch_ready(**k) = record(:batch_ready, k)
    def failure(**k) = record(:failure, k)
  end

  # Fake GraphClient: records drafts, sent mail and uploads, with toggles to fail each.
  class FakeGraphClient
    attr_reader :uploaded, :drafts, :send_mails, :deleted_messages
    attr_accessor :fail_draft, :fail_uploads, :fail_send, :fail_delete_message
    # Recipients whose send raises: an outage hitting some payees but not others.
    attr_accessor :fail_send_to
    # Filenames whose upload raises: one receipt failing to back up while the rest succeed.
    attr_accessor :fail_upload_for
    # What draft_message? reports; false simulates a draft already sent, deleted or unconfirmable.
    attr_accessor :draft_still_exists

    def initialize
      @uploaded = []
      @drafts = []
      @send_mails = []
      @deleted_messages = []
      @fail_send_to = []
      @fail_upload_for = []
      @draft_still_exists = true
    end

    def draft_message?(mailbox:, message_id:)
      @draft_still_exists
    end

    def upload_to_folder(drive_id:, folder_id:, filename:, content:)
      raise ::GraphAuth::Error, "SharePoint down" if fail_uploads
      raise ::GraphAuth::Error, "SharePoint down for #{filename}" if Array(fail_upload_for).include?(filename)

      @uploaded << { drive_id: drive_id, folder_id: folder_id, filename: filename, size: content.bytesize }
      "https://sp.example/#{folder_id}/#{filename}"
    end

    def create_draft(mailbox:, to:, subject:, html:, attachments:)
      raise ::GraphAuth::Error, "draft failed" if fail_draft

      @drafts << { mailbox: mailbox, to: to, subject: subject, html: html,
                   attachments: attachments.map(&:filename) }
      Reimbursements::GraphClient::Draft.new(id: "msg-#{@drafts.size}",
                                             web_link: "https://outlook.example/draft-1")
    end

    def delete_message(mailbox:, message_id:)
      raise ::GraphAuth::Error, "delete failed" if fail_delete_message

      @deleted_messages << { mailbox: mailbox, message_id: message_id }
      nil
    end

    def send_mail(mailbox:, to:, subject:, html:)
      raise ::GraphAuth::Error, "send failed" if fail_send
      if (Array(to) & Array(fail_send_to)).any?
        raise ::GraphAuth::Error, "send failed for #{to.inspect}"
      end

      @send_mails << { mailbox: mailbox, to: to, subject: subject, html: html }
      nil
    end
  end

  private

  def grant_role_permission(user, name, action, subject)
    ::Role.find_by(name: name) || ::Role.create!(name: name).tap do |role|
      role.permissions << Admin::Permission.create(action: action, subject_class: subject)
    end
    user.add_role(name)
  end
end
