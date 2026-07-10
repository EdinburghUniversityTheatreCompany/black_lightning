require "test_helper"

module Reimbursements
  class AiCheckerTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    FakeChat = ReimbursementsTestHelpers::FakeChat

    def receipt(id: "att1", url: "https://airtable/signed/receipt.pdf")
      Attachment.new(attachment_id: id, filename: "receipt.pdf", url: url, content_type: "application/pdf")
    end

    def person(name: "Pat Producer")
      Person.new(record_id: "recPer1", name: name, email: "pat@example.com")
    end

    def budget(name: "Props")
      Budget.new(record_id: "recBud1", name: name, nominal_code: "4000")
    end

    def expense(**attrs)
      defaults = {
        record_id: "recExp1", status: Status::PENDING, auto_number: 1,
        person: person, amount: BigDecimal("12.50"), amount_excl_vat: BigDecimal("10.42"),
        budget: budget, description: "Fake blood", receipts: [ receipt ]
      }
      Expense.new(**defaults.merge(attrs))
    end

    def build(content: nil, error: nil)
      chat = FakeChat.new(content: content, error: error)
      [ AiChecker.new(chat_builder: -> { chat }), chat ]
    end

    test "a passing verdict maps to status pass with its comment" do
      checker, chat = build(content: { "status" => "pass", "comment" => "Looks fine." })

      result = checker.check(expense, [ budget ])

      assert_equal "pass", result.status
      assert_equal "Looks fine.", result.comment
      assert_kind_of Time, result.checked_at
      assert_same AiChecker::SCHEMA, chat.schema
      assert_equal [ "https://airtable/signed/receipt.pdf" ], chat.attachments
    end

    test "a failing verdict maps to status fail" do
      checker, = build(content: { "status" => "fail", "comment" => "Amount doesn't match." })

      result = checker.check(expense, [ budget ])

      assert_equal "fail", result.status
      assert_equal "Amount doesn't match.", result.comment
    end

    test "an unrecognised status is treated as fail" do
      checker, = build(content: { "status" => "maybe", "comment" => "" })
      assert_equal "fail", checker.check(expense, [ budget ]).status
    end

    test "a suggested budget is folded into the comment" do
      checker, = build(content: { "status" => "fail", "comment" => "Wrong category.", "suggested_budget" => "Costumes" })

      result = checker.check(expense, [ budget ])

      assert_equal "Costumes", result.suggested_budget
      assert_includes result.comment, "Suggested budget: Costumes"
    end

    test "returns an error verdict without building a chat when there are no receipts" do
      built = false
      checker = AiChecker.new(chat_builder: -> { built = true; FakeChat.new })

      result = checker.check(expense(receipts: []), [ budget ])

      assert_equal "error", result.status
      assert_match(/No receipts/, result.comment)
      assert_not built
    end

    test "captures a RubyLLM failure as an error verdict" do
      checker, = build(error: RubyLLM::Error.new(nil, "gemini down"))

      result = checker.check(expense, [ budget ])

      assert_equal "error", result.status
      assert_match(/gemini down/, result.comment)
    end

    test "the prompt lists the supplied budgets and asks about VAT" do
      checker, chat = build(content: { "status" => "pass" })
      checker.check(expense, [ budget(name: "Props"), Budget.new(record_id: "recBud2", name: "Costumes") ])

      assert_includes chat.prompt, "Existing budget categories:"
      assert_includes chat.prompt, "- Props"
      assert_includes chat.prompt, "- Costumes"
      assert_match(/VAT/, chat.prompt)
    end

    test "an ordinary expense prompt does not include the third-party override block" do
      checker, chat = build(content: { "status" => "pass" })
      checker.check(expense, [ budget ])

      assert_not_includes chat.prompt, "DIRECT PAYMENT TO A THIRD PARTY"
    end

    test "a payee override adds the third-party verification block to the prompt" do
      checker, chat = build(content: { "status" => "pass" })
      overridden = expense(payee_name_override: "Acme Lighting Ltd",
                           sort_code_override: "20-00-00", account_number_override: "12345678")

      checker.check(overridden, [ budget ])

      assert_includes chat.prompt, "DIRECT PAYMENT TO A THIRD PARTY"
      assert_includes chat.prompt, "Acme Lighting Ltd"
      assert_includes chat.prompt, "20-00-00"
      assert_includes chat.prompt, "12345678"
    end
  end
end
