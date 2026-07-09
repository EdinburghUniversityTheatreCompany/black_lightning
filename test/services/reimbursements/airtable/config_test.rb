require "test_helper"

module Reimbursements
  module Airtable
    class ConfigTest < ActiveSupport::TestCase
      def config
        @config ||= Config.new(
          "base_id" => "appBase1",
          "tables" => { "expenses" => "tblExp", "people" => "tblPpl" },
          "fields" => {
            "expenses" => { "amount" => "fldAmt", "status" => "fldSts" },
            "people" => { "email" => "fldEml" }
          },
          "status_options" => { "pending" => "Pending" }
        )
      end

      test "looks up base, table, field ids and status labels" do
        assert_equal "appBase1", config.base_id
        assert_equal "tblExp", config.table_id(:expenses)
        assert_equal "fldAmt", config.fid(:expenses, :amount)
        assert_equal "Pending", config.status_label(:pending)
      end

      test "reverse-maps a field id to its internal name" do
        assert_equal :status, config.field_name(:expenses, "fldSts")
        assert_nil config.field_name(:expenses, "fldUnknown")
      end

      test "raises KeyError for unknown tables and fields" do
        assert_raises(KeyError) { config.table_id(:batches) }
        assert_raises(KeyError) { config.fid(:expenses, :nope) }
        assert_raises(KeyError) { config.status_label(:archived) }
      end

      test "from_credentials raises a clear error when credentials are missing" do
        error = assert_raises(RuntimeError) { Config.from_credentials }
        assert_match(/reimbursements_airtable/, error.message)
      end
    end
  end
end
