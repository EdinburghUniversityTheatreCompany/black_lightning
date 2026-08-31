# Builders and fakes for reimbursements tests: database seed helpers for the
# DatabaseStore-backed portal, plus fake external-service clients (Graph, HTTP
# transport) and a fake modulus checker.
module ReimbursementsTestHelpers
  # capture_honeybadger_notices moved to test/support/honeybadger_test_helpers.rb
  # when the climate suite needed it too; included here so every existing test
  # keeps calling it unqualified.
  include HoneybadgerTestHelpers

  # --- Database seed helpers -----------------------------------------------
  # Create the real rows the DatabaseStore serves.

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

  # A notification role for a cost centre. Roles are global (not namespaced), so
  # give each one a distinct name or the fixture roles' uniqueness bites.
  def create_reimbursements_role(name:, users: [])
    role = Role.create!(name: name)
    Array(users).each { |user| role.users << user }
    role
  end

  # A cost centre with a notification role attached, since the model requires
  # one. `notification_role: :auto` (the default) builds an EMPTY role, which is
  # what almost every test wants -- it satisfies the validation without silently
  # handing the test an operator mailing list. Pass nil for a centre with no role
  # (the empty-role paths), or a Role to share one.
  def create_reimbursements_cost_centre(key:, name:, eusa_code:,
                                        receive_mailbox: "in@example.com",
                                        send_mailbox: "out@example.com",
                                        notification_role: :auto,
                                        notification_users: [], **attrs)
    role =
      if notification_role == :auto
        create_reimbursements_role(name: "#{name} Finance Admin", users: notification_users)
      else
        notification_role
      end

    Reimbursements::CostCentre.create!(key: key, name: name, eusa_code: eusa_code,
                                       receive_mailbox: receive_mailbox,
                                       send_mailbox: send_mailbox,
                                       notification_role: role, **attrs)
  end

  def create_reimbursements_budget(name: "Props", nominal_code: "4000", active: true,
                                   budget_type: "Expense", initial_budget: nil, notes: nil,
                                   owners: [])
    budget = Reimbursements::Budget.create!(name: name, nominal_code: nominal_code,
                                            active: active, budget_type: budget_type,
                                            initial_budget: initial_budget, notes: notes)
    Array(owners).each { |person| budget.owners << person }
    budget
  end

  def create_reimbursements_expense(person: nil, budget: nil, batch: nil,
                                    status: Reimbursements::Status::PENDING,
                                    amount: BigDecimal("12.5"),
                                    amount_excl_vat: BigDecimal("10.42"),
                                    description: "Fake blood",
                                    payment_reference: "PROPS PAT",
                                    receipt: true, **attrs)
    expense = Reimbursements::Expense.create!(
      person: person, budget: budget, batch: batch, status: status, amount: amount,
      amount_excl_vat: amount_excl_vat, description: description,
      payment_reference: payment_reference, **attrs
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

  def create_reimbursements_batch(date_sent: Date.new(2026, 5, 13), **attrs)
    Reimbursements::Batch.create!(date_sent: date_sent, **attrs)
  end

  def create_reimbursements_actual(nominal_code: "439999", narrative: "Alice Producer",
                                   debit: BigDecimal("123.45"), **attrs)
    Reimbursements::EusaActual.create!(nominal_code: nominal_code, narrative: narrative,
                                       debit: debit, **attrs)
  end

  # --- Assertions ----------------------------------------------------------

  # Every finance list's "Download CSV" answers the same shape: a text/csv
  # attachment named reimbursements-<resource>-<today>.csv. One helper so the
  # six index actions that offer an export assert it identically.
  def assert_csv_download(slug)
    assert_response :success
    assert_includes response.media_type, "text/csv"
    disposition = response.headers["Content-Disposition"]
    assert_match(/attachment/, disposition)
    assert_match(/reimbursements-#{slug}-\d{4}-\d{2}-\d{2}\.csv/, disposition)
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

  # Modulus verdict keyed by account number, so tests don't depend on the
  # gitignored Pay.UK rule files being present.
  class FakeModulusChecker
    def initialize(by_account = {})
      @by_account = by_account
    end

    def check(_sort_code, account_number)
      @by_account.fetch(account_number, ::Reimbursements::ModulusCheck::OUTSIDE_SPEC)
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
  # ::GraphAuth::AuthError to drive the IT-escalation path);
  # +fail_only+ names the alerts that should fail, leaving the rest working —
  # the nightly sends two independent reminders per run, and whether a partly
  # failed run is recorded is exactly what that asymmetry has to prove.
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
    def approved_ready(**k) = record(:approved_ready, k)
    def batch_ready(**k) = record(:batch_ready, k)
    def failure(**k) = record(:failure, k)
  end

  # Fake GraphClient for BatchProcessor / Build Batch / Notifier tests: records
  # drafts, sent mail and uploads, with toggles to make the draft, a send, or
  # uploads fail.
  class FakeGraphClient
    attr_reader :uploaded, :drafts, :send_mails, :deleted_messages
    attr_accessor :fail_draft, :fail_uploads, :fail_send, :fail_delete_message
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

  # The transport fake lives at test/support/fake_http.rb — it is shared with the
  # climate clients and has nothing reimbursements-specific in it. Aliased here so
  # the existing tests keep referring to it unqualified.
  FakeHttp = ::FakeHttp
end
