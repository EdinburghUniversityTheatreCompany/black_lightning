require "test_helper"

module Reimbursements
  class BatchProcessorTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # DatabaseStore with injectable write failures — the DB-era stand-in for
    # FakeAirtableClient's fail_create_tables / fail_update_record_when.
    # +ambiguous_batch_create+ models a lost RESPONSE, not a lost request:
    # the batch really persists but the first call still raises.
    class FlakyStore < DatabaseStore
      attr_accessor :fail_batch_creates, :ambiguous_batch_create, :update_failer

      def create_batch!(attrs)
        @batch_create_calls = (@batch_create_calls || 0) + 1
        raise "create failed for batches" if fail_batch_creates

        if ambiguous_batch_create && @batch_create_calls == 1
          super
          raise "response lost"
        end
        super
      end

      def update_expense!(record_id, attrs)
        raise "blip" if update_failer&.call(record_id.to_s, attrs)

        super
      end
    end

    def configured_cost_centre
      CostCentre.new(key: "fringe", name: "Bedlam Fringe", eusa_code: "F40",
                     receive_mailbox: "in@bedlamfringe.co.uk", send_mailbox: "send@bedlamfringe.co.uk",
                     sharepoint_receipts_drive_id: "drvR", sharepoint_receipts_folder_id: "fldR",
                     sharepoint_bacs_drive_id: "drvB", sharepoint_bacs_folder_id: "fldB")
    end

    def build_scenario(cost_centre: configured_cost_centre, expenses: nil)
      @alice = create_reimbursements_person(name: "Alice", email: "alice@example.com",
                                            sort_code: "08-99-99", account_number: "66374958")
      @bob = create_reimbursements_person(name: "Bob", email: "bob@example.com",
                                          sort_code: "20-20-20", account_number: "50502366")
      @budget = create_reimbursements_budget(name: "Props", nominal_code: "4000")
      expenses || default_expenses
      store = FlakyStore.new
      graph = FakeGraphClient.new
      # The default Notifier sends producer notifications through this same
      # FakeGraphClient (recorded in graph.send_mails), exercising the real
      # producer template render.
      # A no-op sleeper: retry back-off is real in production but must not
      # slow down every retry test in this file.
      processor = BatchProcessor.new(store: store, graph: graph, cost_centre: cost_centre,
                                     sleeper: ->(_seconds) { })
      [ processor, store, graph ]
    end

    def default_expenses
      @expense_a = create_reimbursements_expense(person: @alice, budget: @budget,
                                                 status: Status::APPROVED, auto_number: 11)
      @expense_b = create_reimbursements_expense(person: @bob, budget: @budget,
                                                 status: Status::APPROVED, auto_number: 12)
    end

    def run_batch(processor, store)
      processor.process(expenses: store.expenses, bacs_date: Date.new(2026, 5, 13),
                        sender_name: "Fringe Finance", eusa_recipient: "finance@eusa.ed.ac.uk")
    end

    test "happy path: draft created, batch recorded, expenses submitted, producers notified" do
      processor, store, graph = build_scenario

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

      # Batch record created (storing the draft's message id so a reopen can
      # later verify/delete the stale draft) and both expenses flipped to
      # Submitted + linked.
      batch = Batch.sole
      assert_equal "msg-1", batch.draft_message_id
      [ @expense_a, @expense_b ].each do |expense|
        expense.reload
        assert_equal Status::SUBMITTED, expense.status
        assert_equal batch.record_id, expense.batch_id
        assert expense.receipts_offloaded
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
      assert @expense_a.reload.producer_notified
      assert @expense_b.reload.producer_notified
      assert_equal 2, result.receipts_uploaded, "one receipt per expense; the xlsx isn't counted here"
    end

    test "CARDINAL RULE: a failed draft leaves every expense Approved and no batch" do
      processor, store, graph = build_scenario
      graph.fail_draft = true

      result = run_batch(processor, store)

      assert_not result.success
      assert(result.errors.any? { |e| e.include?("EUSA draft creation failed") })
      assert_equal 0, Batch.count, "no batch when draft fails"
      assert_equal Status::APPROVED, @expense_a.reload.status, "expenses must stay Approved when the draft fails"
      assert_equal Status::APPROVED, @expense_b.reload.status
      assert_empty graph.send_mails, "producers must not be notified when the draft fails"
    end

    test "orphan-draft guard: batch write fails after the draft — no double draft on rebuild" do
      processor, store, graph = build_scenario
      store.fail_batch_creates = true # the draft succeeds; only the Batch write fails

      result = run_batch(processor, store)

      # The draft is live, so the run is NOT a clean failure: it surfaces the
      # orphan loudly (naming the draft link) rather than pretending nothing ran.
      assert_not result.success
      assert_equal 1, graph.drafts.size, "the EUSA draft was created"
      assert(result.errors.any? { |e| e.include?("ORPHAN DRAFT") && e.include?(result.eusa_draft_web_link) })
      assert_equal 0, Batch.count, "no batch record was written"

      # The expenses were marked Submitted anyway, so they leave the Approved
      # queue — nothing for a rebuild to re-draft.
      assert_equal Status::SUBMITTED, @expense_a.reload.status
      assert_equal Status::SUBMITTED, @expense_b.reload.status
      store.bust_expenses!
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
      processor, store, graph = build_scenario
      store.update_failer = ->(record_id, _attrs) { record_id == @expense_a.record_id }

      result = run_batch(processor, store)

      assert_not result.success, "one expense couldn't be marked Submitted — must not report success"
      assert_equal 1, graph.drafts.size, "the EUSA draft was still created and is live"
      assert(result.errors.any? { |e| e.include?("DOUBLE-DRAFT RISK") && e.include?("11") },
             result.errors.inspect)

      # @expense_b still made it through cleanly; @expense_a is the one that failed.
      assert_equal Status::SUBMITTED, @expense_b.reload.status
      assert_equal Status::APPROVED, @expense_a.reload.status

      # @expense_a's payee (Alice) must not be notified — mark_submitted excluded
      # her expense, so notify_producers never saw it.
      assert_equal [ "bob@example.com" ], graph.send_mails.map { |mail| mail[:to] }.flatten
    end

    test "a transient mark_submitted write failure is retried, matching create_batch! and mark_notified" do
      processor, store, graph = build_scenario
      calls = 0
      store.update_failer = lambda do |record_id, attrs|
        next false unless record_id == @expense_a.record_id && attrs[:status] == Status::SUBMITTED

        calls += 1
        calls == 1
      end

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal Status::SUBMITTED, @expense_a.reload.status
      assert_equal Status::SUBMITTED, @expense_b.reload.status
      assert_equal 2, graph.send_mails.size, "both producers were actually emailed"
    end

    test "receipts_offloaded is only stamped true when the receipt upload actually succeeded" do
      processor, store, graph = build_scenario
      graph.fail_uploads = true # every SharePoint upload (BACS xlsx + every receipt) fails

      result = run_batch(processor, store)

      assert result.success, "the draft + submission still succeed; SharePoint uploads are best-effort"
      assert(result.errors.any? { |e| e.include?("SharePoint upload failed") })
      [ @expense_a, @expense_b ].each do |expense|
        expense.reload
        assert_equal Status::SUBMITTED, expense.status
        assert_not expense.receipts_offloaded, "receipts_offloaded must not be true when the upload failed"
      end
    end

    test "a BACS-xlsx SharePoint upload failure doesn't block sending to EUSA or the receipt uploads" do
      processor, store, graph = build_scenario
      bacs_filename = "2026-05-13-bedlam-fringe-BACS-request-F40.xlsx"
      graph.fail_upload_for = [ bacs_filename ]

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert(result.errors.any? { |e| e.include?("BACS file SharePoint upload failed") })
      assert_equal "", result.bacs_sharepoint_url
      assert_equal 1, graph.drafts.size, "the EUSA draft still goes out"
      uploaded_filenames = graph.uploaded.map { |u| u[:filename] }
      assert_not_includes uploaded_filenames, bacs_filename
      assert_equal 2, uploaded_filenames.size, "both receipts still uploaded independently of the xlsx failure"
    end

    test "a single failed receipt upload doesn't corrupt the URL map for that expense or affect others" do
      processor, store, graph = build_scenario(expenses: :custom)
      @multi = create_reimbursements_expense(person: @alice, budget: @budget,
                                             status: Status::APPROVED, auto_number: 11, receipt: false)
      attach_test_receipt(@multi, filename: "receipt1.pdf")
      attach_test_receipt(@multi, filename: "receipt2.pdf")
      @single = create_reimbursements_expense(person: @bob, budget: @budget,
                                              status: Status::APPROVED, auto_number: 12)

      failing_filename = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Props", description: "Fake blood",
        original_filename: "receipt2.pdf", index: 2
      )
      succeeding_filename = FilenameSanitizer.build_receipt_filename(
        bacs_date: Date.new(2026, 5, 13), budget_name: "Props", description: "Fake blood",
        original_filename: "receipt1.pdf", index: 1
      )
      graph.fail_upload_for = [ failing_filename ]

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert(result.errors.any? { |e| e.include?("Receipt upload failed for #{failing_filename}") })

      @multi.reload
      assert_equal [ "https://sp.example/fldR/#{succeeding_filename}" ], @multi.sharepoint_receipt_urls,
                   "only the successful upload's URL is recorded — no nil/phantom entry for the failed one"
      assert_not @multi.receipts_offloaded,
                 "2 receipts but only 1 uploaded — must not be reported as offloaded"

      assert @single.reload.receipts_offloaded,
             "the other expense's single receipt uploaded fine and must be unaffected"
    end

    test "producer_notifications_sent flag is only set when at least one send succeeded" do
      processor, store, graph = build_scenario
      graph.fail_send = true # the draft succeeds; every producer send fails

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 0, result.producer_notifications_sent
      assert_not Batch.sole.producer_notifications_sent,
                 "must not claim notifications were sent when every send failed"
    end

    test "producer_notifications_sent flag is set when there was nothing left to notify" do
      processor, store, graph = build_scenario(expenses: :custom)
      create_reimbursements_expense(person: @alice, budget: @budget, status: Status::APPROVED,
                                    auto_number: 11, producer_notified: true)
      create_reimbursements_expense(person: @bob, budget: @budget, status: Status::APPROVED,
                                    auto_number: 12, producer_notified: true)

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_empty graph.send_mails, "both producers were already notified before this build"
      assert Batch.sole.producer_notifications_sent, "nothing outstanding to notify still counts as complete"
    end

    test "a transient producer_notified write failure is retried, matching create_batch!" do
      processor, store, graph = build_scenario
      calls = 0
      store.update_failer = lambda do |_record_id, attrs|
        next false unless attrs.key?(:producer_notified)

        calls += 1
        calls == 1
      end

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 2, graph.send_mails.size, "both producers were actually emailed"
      assert @expense_a.reload.producer_notified
      assert @expense_b.reload.producer_notified
    end

    test "a transient batch-write failure is retried and the batch still records" do
      processor, store, = build_scenario
      # Fail the first Batch write (nothing persisted), then let the retry through.
      calls = 0
      store.define_singleton_method(:create_batch!) do |attrs|
        calls += 1
        raise "blip" if calls == 1

        super(attrs)
      end

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 1, Batch.count, "the retry recorded the batch"
    end

    test "a retried create_batch after an ambiguous failure reuses the batch instead of duplicating it" do
      processor, store, graph = build_scenario
      # The create actually persists but the caller still sees an error on the
      # first attempt (a network read timeout after the write already
      # committed) — the retry must find and reuse it, not duplicate it.
      store.ambiguous_batch_create = true

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 1, Batch.count, "no SECOND batch record for the same live draft"
      assert_equal 1, graph.drafts.size, "still only one EUSA draft"
    end

    test "refuses to process when SharePoint folders are not configured" do
      cost_centre = configured_cost_centre
      cost_centre.sharepoint_receipts_drive_id = nil
      processor, store, graph = build_scenario(cost_centre: cost_centre)

      result = run_batch(processor, store)

      assert_not result.success
      assert(result.errors.any? { |e| e.include?("SharePoint folders not configured") })
      assert_empty graph.drafts
    end

    test "a receipt-content failure fails the batch cleanly with no draft created" do
      # collect_receipts runs before create_draft (the CARDINAL RULE boundary).
      # On this backend receipts come from ActiveStorage blobs, so the outage
      # is a missing/unreadable blob file; process's method-level rescue
      # reports it as a normal failed Result — nothing has happened yet, so
      # this is safe: no draft, no batch, no Submitted status change.
      processor, store, graph = build_scenario
      @expense_a.receipt_files.each { |attachment| attachment.blob.service.delete(attachment.blob.key) }

      result = run_batch(processor, store)

      assert_not result.success
      assert_not_empty result.errors
      assert_empty graph.drafts
      assert_equal 0, Batch.count
      assert_equal Status::APPROVED, @expense_a.reload.status
      assert_equal Status::APPROVED, @expense_b.reload.status
    end

    test "an empty batch reports an error and touches nothing" do
      processor, = build_scenario
      result = processor.process(expenses: [], bacs_date: Date.new(2026, 5, 13),
                                 sender_name: "F", eusa_recipient: "finance@eusa.ed.ac.uk")

      assert_not result.success
      assert_includes result.errors, "No expenses in batch."
    end

    test "skips producers already notified for this (reopened) batch" do
      processor, store, graph = build_scenario(expenses: :custom)
      create_reimbursements_expense(person: @alice, budget: @budget, status: Status::APPROVED,
                                    auto_number: 11, producer_notified: true)
      create_reimbursements_expense(person: @bob, budget: @budget, status: Status::APPROVED,
                                    auto_number: 12)

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 1, graph.send_mails.size, "only the not-yet-notified producer is emailed"
      assert_equal [ "bob@example.com" ], graph.send_mails.sole[:to]
    end

    test "several expenses for the same payee are grouped into one notification email" do
      processor, store, graph = build_scenario(expenses: :custom)
      alice1 = create_reimbursements_expense(person: @alice, budget: @budget, status: Status::APPROVED,
                                             auto_number: 11, amount: BigDecimal("12.50"),
                                             description: "Fake blood")
      alice2 = create_reimbursements_expense(person: @alice, budget: @budget, status: Status::APPROVED,
                                             auto_number: 12, amount: BigDecimal("7.50"),
                                             description: "Face paint")
      create_reimbursements_expense(person: @bob, budget: @budget, status: Status::APPROVED,
                                    auto_number: 13)

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 2, graph.send_mails.size, "one email per payee, not per expense"
      assert_equal 2, result.producer_notifications_sent, "counted per notification sent, not per expense"

      alice_mail = graph.send_mails.find { |mail| Array(mail[:to]) == [ "alice@example.com" ] }
      assert_includes alice_mail[:subject], "2 expenses submitted for payment"
      assert_includes alice_mail[:html], "Fake blood"
      assert_includes alice_mail[:html], "Face paint"
      assert_includes alice_mail[:html], "£20.00", "the total sums both of Alice's expenses"

      bob_mail = graph.send_mails.find { |mail| Array(mail[:to]) == [ "bob@example.com" ] }
      assert_includes bob_mail[:subject], "1 expense submitted for payment"

      assert alice1.reload.producer_notified
      assert alice2.reload.producer_notified,
             "both of Alice's expenses are stamped, not just one per notification"
    end

    test "a producer notification Graph failure is collected but doesn't fail the batch" do
      processor, store, graph = build_scenario
      graph.fail_send = true # the draft (create_draft) still succeeds; only sends fail

      result = run_batch(processor, store)

      assert result.success, "the batch (draft + submit) still succeeds when a notification send fails"
      assert_empty graph.send_mails
      assert_equal 0, result.producer_notifications_sent
      assert(result.errors.any? { |e| e.include?("Producer notification failed") })
      # The EUSA draft and the expense submissions still happened.
      assert_equal 1, Batch.count
    end

    test "a payee whose notification send fails is not stamped producer_notified" do
      processor, store, graph = build_scenario
      graph.fail_send_to = [ "alice@example.com" ] # Bob's send still succeeds

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert(result.errors.any? { |e| e.include?("Producer notification failed for alice@example.com") })
      # Only Bob was emailed and only Bob is stamped notified — Alice, whose send
      # failed, stays un-notified so a rebuild re-notifies her.
      assert_equal [ "bob@example.com" ], graph.send_mails.map { |m| m[:to] }.flatten
      assert @expense_b.reload.producer_notified
      assert_not @expense_a.reload.producer_notified
    end

    test "custom EUSA subject and body override the composed default" do
      processor, store, graph = build_scenario

      processor.process(expenses: store.expenses, bacs_date: Date.new(2026, 5, 13),
                        sender_name: "F", eusa_recipient: "finance@eusa.ed.ac.uk",
                        eusa_subject: "Custom subject", eusa_body_html: "<p>custom</p>")

      assert_equal "Custom subject", graph.drafts.sole[:subject]
      assert_equal "<p>custom</p>", graph.drafts.sole[:html]
    end
  end
end
