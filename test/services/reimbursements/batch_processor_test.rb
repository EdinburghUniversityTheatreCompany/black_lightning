require "test_helper"

module Reimbursements
  class BatchProcessorTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

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
      graph = FakeGraphClient.new
      # The default Notifier sends producer notifications through this same
      # FakeGraphClient (recorded in graph.send_mails), exercising the real
      # producer template render.
      processor = BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre)
      [ processor, store, client, graph ]
    end

    def run_batch(processor, store)
      processor.process(expenses: store.expenses, bacs_date: Date.new(2026, 5, 13),
                        sender_name: "Fringe Finance", eusa_recipient: "finance@eusa.ed.ac.uk")
    end

    # Overrides +client+'s update_record to raise for calls matching the given
    # predicate, otherwise performing the client's normal write-through — the
    # shared body for tests that need one specific write to fail amid others
    # that must still succeed.
    def fail_update_record_when(client, &predicate)
      client.define_singleton_method(:update_record) do |table, record_id, fields|
        raise Reimbursements::Airtable::Error.new("blip", status: 500) if predicate.call(table, record_id, fields)

        @updated << [ table, record_id, fields ]
        record = @records_by_table.fetch(table, []).find { |r| r["id"] == record_id }
        record["fields"] = record["fields"].merge(fields) if record
        record || { "id" => record_id, "fields" => fields }
      end
    end

    test "happy path: draft created, batch recorded, expenses submitted, producers notified" do
      processor, store, client, graph = build_scenario

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
      # The EUSA draft's message id is stored on the batch (so a reopen can
      # delete the stale draft).
      draft_field = FIELD_IDS[:batches][:draft_message_id]
      batch_write = client.updated.find { |table, _, fields| table == :batches && fields.key?(draft_field) }
      assert_equal "msg-1", batch_write.last[draft_field]
      submitted = client.updated.select { |_, _, fields| fields[FIELD_IDS[:expenses][:status]] == "Submitted" }
      assert_equal 2, submitted.size
      submitted.each do |_, _, fields|
        assert_equal [ result.batch_id ], fields[FIELD_IDS[:expenses][:batch]]
        assert fields[FIELD_IDS[:expenses][:receipts_offloaded]]
      end

      # One producer email per payee, sent via Graph from the send mailbox, and
      # each expense stamped producer_notified.
      assert_equal 2, graph.send_mails.size
      assert_equal 2, result.producer_notifications_sent
      graph.send_mails.each do |mail|
        assert_equal "send@bedlamfringe.co.uk", mail[:mailbox]
        assert_includes mail[:subject], "submitted for payment"
      end
      assert_equal [ "alice@example.com", "bob@example.com" ],
                   graph.send_mails.map { |mail| mail[:to] }.flatten.sort
      notified = client.updated.count { |_, _, fields| fields[FIELD_IDS[:expenses][:producer_notified]] }
      assert_equal 2, notified
      assert_equal 2, result.receipts_uploaded, "one receipt per expense; the xlsx isn't counted here"
    end

    test "CARDINAL RULE: a failed draft leaves every expense Approved and no batch" do
      processor, store, client, graph = build_scenario
      graph.fail_draft = true

      result = run_batch(processor, store)

      assert_not result.success
      assert(result.errors.any? { |e| e.include?("EUSA draft creation failed") })
      assert_equal 0, client.created.count { |table, _| table == :batches }, "no batch when draft fails"
      submitted = client.updated.count { |_, _, fields| fields[FIELD_IDS[:expenses][:status]] == "Submitted" }
      assert_equal 0, submitted, "expenses must stay Approved when the draft fails"
      assert_empty graph.send_mails, "producers must not be notified when the draft fails"
    end

    test "orphan-draft guard: batch write fails after the draft — no double draft on rebuild" do
      processor, store, client, graph = build_scenario
      client.fail_create_tables = [ :batches ] # the draft succeeds; only the Batch write fails

      result = run_batch(processor, store)

      # The draft is live, so the run is NOT a clean failure: it surfaces the
      # orphan loudly (naming the draft link) rather than pretending nothing ran.
      assert_not result.success
      assert_equal 1, graph.drafts.size, "the EUSA draft was created"
      assert(result.errors.any? { |e| e.include?("ORPHAN DRAFT") && e.include?(result.eusa_draft_web_link) })
      assert_equal 0, client.created.count { |table, _| table == :batches }, "no batch record was written"

      # The expenses were marked Submitted anyway, so they leave the Approved
      # queue — nothing for a rebuild to re-draft.
      submitted = client.updated.count { |_, _, fields| fields[FIELD_IDS[:expenses][:status]] == "Submitted" }
      assert_equal 2, submitted
      approved_now = store.expenses.select { |e| e.status == Status::APPROVED }
      assert_empty approved_now, "no expense stays Approved with a live draft"

      # Producers are still notified on the orphan-draft path — the expense IS
      # Submitted and the payee's money IS on its way, orphan Batch record or not.
      assert_equal 2, graph.send_mails.size
      assert_equal 2, result.producer_notifications_sent

      # Rebuild: the operator's approved set is now empty, so a second process
      # makes NO second draft — the guarantee that prevents a duplicate payment.
      rebuild = processor.process(expenses: approved_now, bacs_date: Date.new(2026, 5, 13),
                                  sender_name: "F", eusa_recipient: "finance@eusa.ed.ac.uk")
      assert_not rebuild.success
      assert_equal 1, graph.drafts.size, "no SECOND draft on rebuild"
    end

    test "a mark_submitted write failure is a double-draft risk, not swallowed as success" do
      processor, store, client, graph = build_scenario
      fail_update_record_when(client) { |_table, record_id, _fields| record_id == "recExpA" }

      result = run_batch(processor, store)

      assert_not result.success, "one expense couldn't be marked Submitted — must not report success"
      assert_equal 1, graph.drafts.size, "the EUSA draft was still created and is live"
      assert(result.errors.any? { |e| e.include?("DOUBLE-DRAFT RISK") && e.include?("11") },
             result.errors.inspect)

      # recExpB still made it through cleanly; recExpA is the one that failed.
      assert_equal [ "recExpB" ], store.expenses.select { |e| e.status == Status::SUBMITTED }.map(&:record_id)
      assert_equal [ "recExpA" ], store.expenses.select { |e| e.status == Status::APPROVED }.map(&:record_id)

      # recExpA's payee (Alice) must not be notified — mark_submitted excluded
      # her expense, so notify_producers never saw it.
      assert_equal [ "bob@example.com" ], graph.send_mails.map { |mail| mail[:to] }.flatten
    end

    test "receipts_offloaded is only stamped true when the receipt upload actually succeeded" do
      processor, store, client, graph = build_scenario
      graph.fail_uploads = true # every SharePoint upload (BACS xlsx + every receipt) fails

      result = run_batch(processor, store)

      assert result.success, "the draft + submission still succeed; SharePoint uploads are best-effort"
      assert(result.errors.any? { |e| e.include?("SharePoint upload failed") })
      offload_field = FIELD_IDS[:expenses][:receipts_offloaded]
      submitted_writes = client.updated.select { |_, _, fields| fields[FIELD_IDS[:expenses][:status]] == "Submitted" }
      assert_equal 2, submitted_writes.size
      submitted_writes.each do |_, _, fields|
        assert_not fields[offload_field], "receipts_offloaded must not be true when the upload failed"
      end
    end

    test "producer_notifications_sent flag is only set when at least one send succeeded" do
      processor, store, client, graph = build_scenario
      graph.fail_send = true # the draft succeeds; every producer send fails

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 0, result.producer_notifications_sent
      notif_field = FIELD_IDS[:batches][:producer_notifications_sent]
      batch_writes = client.updated.select { |table, _, fields| table == :batches && fields.key?(notif_field) }
      assert_empty batch_writes, "must not claim notifications were sent when every send failed"
    end

    test "a transient producer_notified write failure is retried, matching create_batch!" do
      processor, store, client, graph = build_scenario
      calls = 0
      field = FIELD_IDS[:expenses][:producer_notified]
      fail_update_record_when(client) do |table, _record_id, fields|
        next false unless table == :expenses && fields.key?(field)

        calls += 1
        calls == 1
      end

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 2, graph.send_mails.size, "both producers were actually emailed"
      notified = client.updated.count { |_, _, fields| fields[FIELD_IDS[:expenses][:producer_notified]] }
      assert_equal 2, notified, "the retry recorded the stamp that failed on the first attempt"
    end

    test "a transient batch-write failure is retried and the batch still records" do
      processor, store, client, _graph = build_scenario
      # Fail the first Batch write, then let the retry through.
      calls = 0
      client.define_singleton_method(:create_record) do |table, fields|
        if table == :batches
          calls += 1
          raise Reimbursements::Airtable::Error.new("blip", status: 500) if calls == 1
        end
        @created << [ table, fields ]
        { "id" => "recNew#{@created.size}", "fields" => fields }
      end

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 1, client.created.count { |table, _| table == :batches }, "the retry recorded the batch"
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
      processor, store, _client, graph = build_scenario(expenses: [ already, fresh ])

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 1, graph.send_mails.size, "only the not-yet-notified producer is emailed"
      assert_equal [ "bob@example.com" ], graph.send_mails.sole[:to]
    end

    test "a producer notification Graph failure is collected but doesn't fail the batch" do
      processor, store, client, graph = build_scenario
      graph.fail_send = true # the draft (create_draft) still succeeds; only sends fail

      result = run_batch(processor, store)

      assert result.success, "the batch (draft + submit) still succeeds when a notification send fails"
      assert_empty graph.send_mails
      assert_equal 0, result.producer_notifications_sent
      assert(result.errors.any? { |e| e.include?("Producer notification failed") })
      # The EUSA draft and the expense submissions still happened.
      assert_equal 1, client.created.count { |table, _| table == :batches }
    end

    test "a payee whose notification send fails is not stamped producer_notified" do
      processor, store, client, graph = build_scenario
      graph.fail_send_to = [ "alice@example.com" ] # Bob's send still succeeds

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert(result.errors.any? { |e| e.include?("Producer notification failed for alice@example.com") })
      # Only Bob was emailed and only Bob is stamped notified — Alice, whose send
      # failed, stays un-notified so a rebuild re-notifies her.
      assert_equal [ "bob@example.com" ], graph.send_mails.map { |m| m[:to] }.flatten
      notified_ids = client.updated.select { |_, _, f| f[FIELD_IDS[:expenses][:producer_notified]] }.map { |_, id, _| id }
      assert_equal [ "recExpB" ], notified_ids
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
