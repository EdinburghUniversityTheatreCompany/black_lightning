require "test_helper"

module Reimbursements
  class BatchProcessorTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    class FakeGraph
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
        raise GraphAuth::Error, "SharePoint down" if @fail_uploads

        @uploaded << { drive_id: drive_id, folder_id: folder_id, filename: filename, size: content.bytesize }
        "https://sp.example/#{folder_id}/#{filename}"
      end

      def create_draft(mailbox:, to:, subject:, html:, attachments:)
        raise GraphAuth::Error, "draft failed" if @fail_draft

        @drafts << { mailbox: mailbox, to: to, subject: subject, html: html,
                     attachments: attachments.map(&:filename) }
        "https://outlook.example/draft-1"
      end
    end

    FakeDelivery = Struct.new(:noop) do
      def deliver_later = nil
    end

    class FakeMailer
      attr_reader :sent

      def initialize
        @sent = []
      end

      def producer_notification(**kwargs)
        @sent << kwargs
        FakeDelivery.new
      end
    end

    def configured_cost_centre
      CostCentre.new(key: "fringe", name: "Bedlam Fringe", eusa_code: "F40",
                     receive_mailbox: "in@bedlamfringe.co.uk", send_mailbox: "send@bedlamfringe.co.uk",
                     sharepoint_receipts_drive_id: "drvR", sharepoint_receipts_folder_id: "fldR",
                     sharepoint_bacs_drive_id: "drvB", sharepoint_bacs_folder_id: "fldB")
    end

    def build_scenario(cost_centre: configured_cost_centre, expenses: nil)
      people = [
        airtable_person_record(id: "recAlice", name: "Alice", email: "alice@example.com",
                               sort_code: "08-99-99", account_number: "66374958"),
        airtable_person_record(id: "recBob", name: "Bob", email: "bob@example.com",
                               sort_code: "20-20-20", account_number: "50502366")
      ]
      budgets = [ airtable_budget_record(id: "recBud1", name: "Props", nominal_code: "4000") ]
      expenses ||= [
        airtable_expense_record(id: "recExpA", payee_id: "recAlice", status: "Approved", auto_number: 11),
        airtable_expense_record(id: "recExpB", payee_id: "recBob", status: "Approved", auto_number: 12)
      ]
      store, client = build_fake_store(expenses: expenses, people: people, budgets: budgets)
      graph = FakeGraph.new
      mailer = FakeMailer.new
      processor = BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre, mailer: mailer)
      [ processor, store, client, graph, mailer ]
    end

    def run_batch(processor, store)
      processor.process(expenses: store.expenses, bacs_date: Date.new(2026, 5, 13),
                        sender_name: "Fringe Finance", eusa_recipient: "finance@eusa.ed.ac.uk")
    end

    test "happy path: draft created, batch recorded, expenses submitted, producers notified" do
      processor, store, client, graph, mailer = build_scenario

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_empty result.errors

      # EUSA draft in the send mailbox, addressed to EUSA, with xlsx + both receipts attached.
      draft = graph.drafts.sole
      assert_equal "send@bedlamfringe.co.uk", draft[:mailbox]
      assert_equal [ "finance@eusa.ed.ac.uk" ], draft[:to]
      assert_includes draft[:subject], "F40"
      xlsx = draft[:attachments].find { |name| name.end_with?(".xlsx") }
      assert_equal "2026-05-13-bedlam-fringe-BACS-request-F40.xlsx", xlsx
      assert_equal 3, draft[:attachments].size, "xlsx + one receipt per expense"

      # Batch record created and both expenses flipped to Submitted + linked.
      assert_equal 1, client.created.count { |table, _| table == :batches }
      submitted = client.updated.select { |_, _, fields| fields[FIELD_IDS[:expenses][:status]] == "Submitted" }
      assert_equal 2, submitted.size
      submitted.each do |_, _, fields|
        assert_equal [ result.batch_id ], fields[FIELD_IDS[:expenses][:batch]]
        assert fields[FIELD_IDS[:expenses][:receipts_offloaded]]
      end

      # One producer email per payee, and each expense stamped producer_notified.
      assert_equal 2, mailer.sent.size
      assert_equal 2, result.producer_notifications_sent
      notified = client.updated.count { |_, _, fields| fields[FIELD_IDS[:expenses][:producer_notified]] }
      assert_equal 2, notified
      assert_equal 2, result.receipts_uploaded, "one receipt per expense; the xlsx isn't counted here"
    end

    test "CARDINAL RULE: a failed draft leaves every expense Approved and no batch" do
      processor, store, client, graph, mailer = build_scenario
      graph.fail_draft = true

      result = run_batch(processor, store)

      assert_not result.success
      assert(result.errors.any? { |e| e.include?("EUSA draft creation failed") })
      assert_equal 0, client.created.count { |table, _| table == :batches }, "no batch when draft fails"
      submitted = client.updated.count { |_, _, fields| fields[FIELD_IDS[:expenses][:status]] == "Submitted" }
      assert_equal 0, submitted, "expenses must stay Approved when the draft fails"
      assert_empty mailer.sent, "producers must not be notified when the draft fails"
    end

    test "refuses to process when SharePoint folders are not configured" do
      cost_centre = configured_cost_centre
      cost_centre.sharepoint_receipts_drive_id = nil
      processor, store, _client, graph = build_scenario(cost_centre: cost_centre)

      result = run_batch(processor, store)

      assert_not result.success
      assert(result.errors.any? { |e| e.include?("SharePoint folders not configured") })
      assert_empty graph.drafts
    end

    test "an empty batch reports an error and touches nothing" do
      processor, = build_scenario
      result = processor.process(expenses: [], bacs_date: Date.new(2026, 5, 13),
                                 sender_name: "F", eusa_recipient: "finance@eusa.ed.ac.uk")

      assert_not result.success
      assert_includes result.errors, "No expenses in batch."
    end

    test "skips producers already notified for this (reopened) batch" do
      already = airtable_expense_record(id: "recExpA", payee_id: "recAlice", status: "Approved",
                                        auto_number: 11,
                                        overrides: { FIELD_IDS[:expenses][:producer_notified] => true })
      fresh = airtable_expense_record(id: "recExpB", payee_id: "recBob", status: "Approved", auto_number: 12)
      processor, store, _client, _graph, mailer = build_scenario(expenses: [ already, fresh ])

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 1, mailer.sent.size, "only the not-yet-notified producer is emailed"
      assert_equal "bob@example.com", mailer.sent.sole[:recipient_email]
    end

    test "custom EUSA subject and body override the composed default" do
      processor, store, _client, graph = build_scenario

      processor.process(expenses: store.expenses, bacs_date: Date.new(2026, 5, 13),
                        sender_name: "F", eusa_recipient: "finance@eusa.ed.ac.uk",
                        eusa_subject: "Custom subject", eusa_body_html: "<p>custom</p>")

      assert_equal "Custom subject", graph.drafts.sole[:subject]
      assert_equal "<p>custom</p>", graph.drafts.sole[:html]
    end
  end
end
