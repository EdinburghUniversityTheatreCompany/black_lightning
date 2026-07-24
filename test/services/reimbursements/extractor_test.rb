require "test_helper"

module Reimbursements
  class ExtractorTest < ActiveSupport::TestCase
    # The Extractor reads the budgets' public interface (name, nominal_code,
    # record_id) to build the prompt and match a suggestion; built unpersisted
    # with record_id pinned.
    Budget = Reimbursements::Budget

    include ReimbursementsTestHelpers

    RECEIPT = { filename: "receipt.pdf", content_type: "application/pdf", bytes: "PDF" }.freeze
    FakeChat = ReimbursementsTestHelpers::FakeChat

    def budgets
      budget = Budget.new(name: "Props", nominal_code: "4000")
      budget.define_singleton_method(:record_id) { "recBud1" }
      [ budget ]
    end

    def build_extractor(content: nil, error: nil)
      chat = FakeChat.new(content: content, error: error)
      extractor = Extractor.new(api_key: "gem-test", chat_builder: -> { chat })
      [ extractor, chat ]
    end

    def happy_content
      {
        "merchant" => "Edinburgh Bargain Stores", "purchase_date" => "2026-07-01",
        "total_amount" => 12.5, "vat_amount" => 2.08, "vat_itemised" => true,
        "suggested_description" => "Props for main show",
        "suggested_budget_record_id" => "recBud1",
        "suggested_payment_reference" => "A VERY LONG REFERENCE INDEED"
      }
    end

    def invoice_content
      happy_content.merge(
        "payee_name" => "Acme Props Ltd", "sort_code" => "12-34-56",
        "account_number" => "12345678"
      )
    end

    test "parses a successful extraction" do
      extractor, chat = build_extractor(content: happy_content)

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert result.ok?
      assert_equal "Edinburgh Bargain Stores", result.merchant
      assert_equal Date.new(2026, 7, 1), result.purchase_date
      assert_equal BigDecimal("12.5"), result.total_amount
      assert_equal BigDecimal("2.08"), result.vat_amount
      assert result.vat_itemised
      assert_equal "recBud1", result.suggested_budget_record_id
      assert_equal 18, result.suggested_payment_reference.length, "reference must be truncated to 18 chars"

      # The receipt bytes are handed to RubyLLM as an attachment, PDF detected
      # from the filename.
      attachment = chat.attachments.sole
      assert_instance_of RubyLLM::Attachment, attachment
      assert_equal "application/pdf", attachment.mime_type
      assert_same Extractor::SCHEMA, chat.schema
    end

    test "derives amount_excl_vat only when VAT is itemised" do
      extractor, = build_extractor(content: happy_content)
      assert_equal BigDecimal("10.42"), extractor.extract(receipts: [ RECEIPT ], budgets: budgets).amount_excl_vat

      extractor, = build_extractor(content: happy_content.merge("vat_itemised" => false))
      assert_nil extractor.extract(receipts: [ RECEIPT ], budgets: budgets).amount_excl_vat
    end

    test "discards a suggested budget that is not in the provided list" do
      extractor, = build_extractor(content: happy_content.merge("suggested_budget_record_id" => "recBogus"))

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert result.ok?
      assert_nil result.suggested_budget_record_id
    end

    test "self mode (the default) uses the base schema and never returns bank details" do
      extractor, chat = build_extractor(content: invoice_content)

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert result.ok?
      assert_same Extractor::SCHEMA, chat.schema, "self mode must not request the bank-detail schema"
      assert_nil result.payee_name, "self mode never surfaces payee bank details"
      assert_nil result.sort_code
      assert_nil result.account_number
    end

    test "self mode is what an explicit :self asks for too" do
      extractor, chat = build_extractor(content: invoice_content)

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets, mode: :self)

      assert result.ok?
      assert_same Extractor::SCHEMA, chat.schema
      assert_nil result.account_number
    end

    test "invoice mode requests the bank-detail schema and returns the printed details" do
      extractor, chat = build_extractor(content: invoice_content)

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets, mode: :invoice)

      assert result.ok?
      assert_same Extractor::INVOICE_SCHEMA, chat.schema
      assert_equal "Acme Props Ltd", result.payee_name
      assert_equal "12-34-56", result.sort_code
      assert_equal "12345678", result.account_number
      # The everyday fields still come through in invoice mode.
      assert_equal BigDecimal("12.5"), result.total_amount
      assert_equal "recBud1", result.suggested_budget_record_id
    end

    test "invoice mode asks the model for bank details only when printed on the invoice" do
      extractor, chat = build_extractor(content: invoice_content)

      extractor.extract(receipts: [ RECEIPT ], budgets: budgets, mode: :invoice)

      assert_match(/payee_name/, chat.prompt)
      assert_match(/sort_code/, chat.prompt)
      assert_match(/account_number/, chat.prompt)
      assert_match(/only if.*printed on the invoice/i, chat.prompt)
    end

    test "invoice mode omits bank fields the receipt did not print" do
      extractor, = build_extractor(content: happy_content) # no bank keys in the payload

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets, mode: :invoice)

      assert result.ok?
      assert_nil result.payee_name
      assert_nil result.sort_code
      assert_nil result.account_number
    end

    test "fails gracefully when the model returns a non-object payload" do
      extractor, = build_extractor(content: "just a string")

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)
      assert_not result.ok?
    end

    test "fails gracefully when the RubyLLM call raises" do
      extractor, = build_extractor(error: RubyLLM::Error.new(nil, "gemini down"))

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert_not result.ok?
      assert_match(/gemini down/, result.error)
    end

    test "fails gracefully on a generic error, not just a RubyLLM one" do
      extractor, = build_extractor(error: StandardError.new("network timeout"))

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert_not result.ok?
      assert_match(/network timeout/, result.error)
    end

    test "fails without building a chat when no key is configured" do
      built = false
      extractor = Extractor.new(api_key: nil, chat_builder: -> { built = true; FakeChat.new })

      result = extractor.extract(receipts: [ RECEIPT ], budgets: budgets)

      assert_not result.ok?
      assert_match(/key/i, result.error)
      assert_not built, "must not build a chat without an API key"
    end

    test "fails without building a chat when no receipts are given" do
      built = false
      extractor = Extractor.new(api_key: "gem-test", chat_builder: -> { built = true; FakeChat.new })

      result = extractor.extract(receipts: [], budgets: budgets)

      assert_not result.ok?
      assert_not built, "must not build a chat with no receipts"
    end
  end
end
