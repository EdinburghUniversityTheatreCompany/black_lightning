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
      initial_budget: "fldBudInit", remaining: "fldBudRem", budget_type: "fldBudType"
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
      ai_comment: "fldExpAiCom", ai_checked_at: "fldExpAiAt"
    }
  }.freeze

  def reimbursements_test_config
    Reimbursements::Airtable::Config.new(
      base_id: "appTestBase",
      tables: { people: "tblPeople", budgets: "tblBudgets", expenses: "tblExpenses" },
      fields: FIELD_IDS,
      status_options: {
        pending: "Pending", approved: "Approved", submitted: "Submitted",
        paid: "Paid", rejected: "Rejected"
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

  def airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000", active: true)
    f = FIELD_IDS[:budgets]
    { "id" => id,
      "fields" => { f[:name] => name, f[:nominal_code] => nominal_code, f[:active] => active }.compact }
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
        { "id" => "att1", "filename" => "receipt.pdf", "url" => "https://airtable/signed", "size" => 1234, "type" => "application/pdf" }
      ])
    }
    fields.delete_if { |_, v| v.nil? || v == [] }
    fields.merge!(overrides)
    { "id" => id, "fields" => fields }
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
