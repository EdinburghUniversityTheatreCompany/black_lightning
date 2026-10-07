require "test_helper"

module Reimbursements
  class BatchProcessorTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # DatabaseStore with injectable write failures. +ambiguous_batch_create+ is
    # a lost RESPONSE: the batch persists but the first call still raises.
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
      (expenses || method(:default_expenses)).call
      store = FlakyStore.new
      # The real Notifier sends producer emails through this fake (graph.send_mails).
      graph = FakeGraphClient.new
      # A no-op sleeper, so the retry back-off does not slow the tests.
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

    def table_cells(html)
      Nokogiri::HTML(html).css("td").map { |cell| cell.text.strip }
    end

    def run_batch(processor, store)
      processor.process(expenses: store.expenses, bacs_date: Date.new(2026, 5, 13),
                        sender_name: "Fringe Finance", eusa_recipient: "finance@eusa.ed.ac.uk")
    end

    # --- Mixed and international batches ------------------------------------

    def international_expense(auto_number: 21, **attrs)
      create_reimbursements_expense(
        person: @alice, budget: @budget, status: Status::APPROVED, auto_number: auto_number,
        payment_method: Expense::PAYMENT_METHOD_INTERNATIONAL,
        foreign_amount: BigDecimal("266.69"), foreign_currency: Expense::CURRENCY_EUR,
        payee_name_override: "Ausland GmbH",
        iban_override: "DE89370400440532013000", bic_override: "DEUTDEFF500", **attrs
      )
    end

    # FakeGraphClient already records attachments as their filenames.
    def attached_filenames(graph)
      graph.drafts.first[:attachments]
    end

    test "a mixed batch attaches and backs up the BACS sheet plus one form per international claim" do
      processor, store, graph = build_scenario(expenses: -> { default_expenses; international_expense })
      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      names = attached_filenames(graph)
      assert_includes names, "2026-05-13-bedlam-fringe-BACS-request-F40.xlsx"
      assert_includes names, "2026-05-13-bedlam-fringe-international-payment-Ausland GmbH-#21.xlsx"

      uploaded = graph.uploaded.map { |u| u[:filename] }
      assert_includes uploaded, "2026-05-13-bedlam-fringe-BACS-request-F40.xlsx"
      assert_includes uploaded, "2026-05-13-bedlam-fringe-international-payment-Ausland GmbH-#21.xlsx"
    end

    test "two international claims get a form each, told apart by claim number" do
      processor, store, graph = build_scenario(expenses: lambda {
        international_expense(auto_number: 21)
        international_expense(auto_number: 22)
      })
      run_batch(processor, store)

      names = attached_filenames(graph)
      assert_includes names, "2026-05-13-bedlam-fringe-international-payment-Ausland GmbH-#21.xlsx"
      assert_includes names, "2026-05-13-bedlam-fringe-international-payment-Ausland GmbH-#22.xlsx"
    end

    # The rail changes the paperwork, not the bookkeeping.
    test "an all-international batch attaches one form and no BACS sheet, and goes through the same post-draft path" do
      processor, store, graph = build_scenario(expenses: -> { international_expense })
      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      names = attached_filenames(graph)
      # An empty BACS sheet would ask EUSA to pay nobody.
      assert_not(names.any? { |name| name.include?("BACS-request") })
      assert_equal 1, names.count { |name| name.include?("international-payment") }

      expense = store.expenses.first
      assert_equal Status::SUBMITTED, expense.status
      assert_equal result.batch_id, expense.batch_id
      assert_equal 1, graph.send_mails.size

      # EUSA's bank pays in euros; GBP beside a form saying EUR reads as a discrepancy.
      body = graph.drafts.first[:html]
      assert_includes body, "€266.69"
      assert_includes body, "international payment request form"
    end

    test "happy path: draft created, batch recorded, expenses submitted, producers notified" do
      processor, store, graph = build_scenario

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_empty result.errors

      draft = graph.drafts.sole
      assert_equal "send@bedlamfringe.co.uk", draft[:mailbox]
      assert_equal [ "finance@eusa.ed.ac.uk" ], draft[:to]
      assert_includes draft[:subject], "F40"
      assert_not_includes draft[:html], "international payment request form", "a UK-only batch says nothing about it"
      xlsx = draft[:attachments].find { |name| name.end_with?(".xlsx") }
      assert_equal "2026-05-13-bedlam-fringe-BACS-request-F40.xlsx", xlsx
      assert_equal 3, draft[:attachments].size, "xlsx + one receipt per expense"

      batch = Batch.sole
      assert_equal "msg-1", batch.draft_message_id
      # Graph returns the webLink only once, so the batch must keep it.
      assert_equal "https://outlook.example/draft-1", batch.draft_web_link
      [ @expense_a, @expense_b ].each do |expense|
        expense.reload
        assert_equal Status::SUBMITTED, expense.status
        assert_equal batch.record_id, expense.batch_id
        assert expense.receipts_offloaded
      end

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

    # Each surface reads Budget#display_name, so each names the show.
    test "a batch's receipt filenames, producer email and EUSA draft all name the show" do
      processor, store, graph = build_scenario
      @budget.update!(area: create_reimbursements_area(name: "Cogito"))

      run_batch(processor, store)

      graph.uploaded.reject { |upload| upload[:filename].end_with?(".xlsx") }.each do |upload|
        # FilenameSanitizer turns the colon (illegal in SharePoint) into a space.
        assert_includes upload[:filename], "Cogito Props",
                        "a receipt filename that names no show is indistinguishable from another show's"
      end
      # The table CELL: both templates carry other prose a substring could match.
      assert_includes table_cells(graph.send_mails.first[:html]), "Cogito: Props"
      assert_includes table_cells(graph.drafts.sole[:html]), "Cogito: Props"
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

    test "orphan-draft guard: batch write fails after the draft: no double draft on rebuild" do
      processor, store, graph = build_scenario
      store.fail_batch_creates = true # the draft succeeds; only the Batch write fails

      result = run_batch(processor, store)

      assert_not result.success
      assert_equal 1, graph.drafts.size, "the EUSA draft was created"
      assert(result.errors.any? { |e| e.include?("ORPHAN DRAFT") && e.include?(result.eusa_draft_web_link) })
      assert_equal 0, Batch.count, "no batch record was written"

      # Submitted anyway, so a rebuild has nothing to re-draft.
      assert_equal Status::SUBMITTED, @expense_a.reload.status
      assert_equal Status::SUBMITTED, @expense_b.reload.status
      store.bust_expenses!
      approved_now = store.expenses.select { |e| e.status == Status::APPROVED }
      assert_empty approved_now, "no expense stays Approved with a live draft"

      # Producers are still notified: their money IS on its way.
      assert_equal 2, graph.send_mails.size
      assert_equal 2, result.producer_notifications_sent

      # The guarantee against a duplicate payment: a rebuild makes no second draft.
      rebuild = processor.process(expenses: approved_now, bacs_date: Date.new(2026, 5, 13),
                                  sender_name: "F", eusa_recipient: "finance@eusa.ed.ac.uk")
      assert_not rebuild.success
      assert_equal 1, graph.drafts.size, "no SECOND draft on rebuild"
    end

    test "a mark_submitted write failure is a double-draft risk, not swallowed as success" do
      processor, store, graph = build_scenario
      store.update_failer = ->(record_id, _attrs) { record_id == @expense_a.record_id }

      result = run_batch(processor, store)

      assert_not result.success, "one expense couldn't be marked Submitted: must not report success"
      assert_equal 1, graph.drafts.size, "the EUSA draft was still created and is live"
      assert(result.errors.any? { |e| e.include?("DOUBLE-DRAFT RISK") && e.include?("11") },
             result.errors.inspect)

      assert_equal Status::SUBMITTED, @expense_b.reload.status
      assert_equal Status::APPROVED, @expense_a.reload.status

      # Alice's expense was excluded, so she is not notified.
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
      graph.fail_uploads = true # the BACS xlsx and every receipt

      result = run_batch(processor, store)

      assert result.success, "the draft + submission still succeed; SharePoint uploads are best-effort"
      assert(result.errors.any? { |e| e.include?("SharePoint upload failed") })
      [ @expense_a, @expense_b ].each do |expense|
        expense.reload
        assert_equal Status::SUBMITTED, expense.status
        assert_not expense.receipts_offloaded, "receipts_offloaded must not be true when the upload failed"
      end
    end

    # Through the REAL GraphClient, which owns the outbound gate: a dev shell with
    # real Azure credentials must not PUT full bank details into production
    # SharePoint, nor record receipts_offloaded for files never written.
    test "a batch built with outbound disabled issues no Graph request and offloads nothing" do
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")
      build_scenario
      store = FlakyStore.new
      http = FakeHttp.new([]) # any request at all would raise "no queued response"
      graph = GraphClient.new(settings: Settings, http: http, clock: -> { Time.current })
      processor = BatchProcessor.new(store: store, graph: graph, cost_centre: configured_cost_centre,
                                    sleeper: ->(_seconds) { })

      result = run_batch(processor, store)

      assert_empty http.requests,
                   "no Graph request may leave a non-production environment, token exchange included"
      assert_equal "", result.bacs_sharepoint_url
      assert_equal 0, result.receipts_uploaded
      assert(result.errors.any? { |e| e.include?("SharePoint upload failed for") },
             "the suppression is surfaced, not silent: #{result.errors.inspect}")
      store.expenses.each do |expense|
        assert_not expense.receipts_offloaded,
                   "a suppressed upload must never be recorded as an offloaded receipt"
      end
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    test "a BACS-xlsx SharePoint upload failure doesn't block sending to EUSA or the receipt uploads" do
      processor, store, graph = build_scenario
      bacs_filename = "2026-05-13-bedlam-fringe-BACS-request-F40.xlsx"
      graph.fail_upload_for = [ bacs_filename ]

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert(result.errors.any? { |e| e.include?("SharePoint upload failed for #{bacs_filename}") },
             "the failure names the document that failed: #{result.errors.inspect}")
      assert_equal "", result.bacs_sharepoint_url
      assert_equal 1, graph.drafts.size, "the EUSA draft still goes out"
      uploaded_filenames = graph.uploaded.map { |u| u[:filename] }
      assert_not_includes uploaded_filenames, bacs_filename
      assert_equal 2, uploaded_filenames.size, "both receipts still uploaded independently of the xlsx failure"
    end

    test "a single failed receipt upload doesn't corrupt the URL map for that expense or affect others" do
      processor, store, graph = build_scenario(expenses: -> { })
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
                   "only the successful upload's URL is recorded: no nil/phantom entry for the failed one"
      assert_not @multi.receipts_offloaded,
                 "2 receipts but only 1 uploaded: must not be reported as offloaded"

      assert @single.reload.receipts_offloaded,
             "the other expense's single receipt uploaded fine and must be unaffected"
    end

    test "a producer notification failure is collected, doesn't fail the batch and leaves it unflagged" do
      processor, store, graph = build_scenario
      graph.fail_send = true # the draft succeeds; every producer send fails

      result = run_batch(processor, store)

      assert result.success, "the batch (draft + submit) still succeeds when a notification send fails"
      assert_empty graph.send_mails
      assert(result.errors.any? { |e| e.include?("Producer notification failed") })
      assert_not Batch.sole.producer_notifications_sent,
                 "must not claim notifications were sent when every send failed"
    end

    test "producer_notifications_sent flag is set when there was nothing left to notify" do
      processor, store, graph = build_scenario(expenses: -> { })
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
      # The first Batch write fails with nothing persisted.
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
      # The first create commits but still raises (a read timeout after the write).
      store.ambiguous_batch_create = true

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert_equal 1, Batch.count, "no SECOND batch record for the same live draft"
      assert_equal 1, graph.drafts.size, "still only one EUSA draft"
    end

    # The approve blocker runs on the approval path only, so a claim that reached
    # Approved another way (an import, a console fix) can arrive with no bank
    # details. 140 production claims sat in that state in September 2026.
    test "refuses to process a claim with no bank details" do
      processor, store, graph = build_scenario(expenses: lambda {
        @expense_a = create_reimbursements_expense(person: @alice, budget: @budget,
                                                   status: Status::APPROVED, auto_number: 11)
        payeeless = create_reimbursements_person(name: "No Bank", email: "nobank@example.com",
                                                 sort_code: "", account_number: "")
        @expense_b = create_reimbursements_expense(person: payeeless, budget: @budget,
                                                   status: Status::APPROVED, auto_number: 12)
      })

      result = run_batch(processor, store)

      assert_not result.success
      assert(result.errors.any? { |e| e.include?("no bank details") },
             "the failure must say what is wrong: #{result.errors.inspect}")
      assert(result.errors.any? { |e| e.include?("12") },
             "the failure must name the claim: #{result.errors.inspect}")
      assert_empty graph.drafts, "nothing may reach EUSA"
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
      # Receipts are read before the draft, so a missing blob fails cleanly.
      processor, store, graph = build_scenario
      @expense_a.receipt_files.each { |attachment| attachment.blob.service.delete(attachment.blob.key) }

      before_a = @expense_a.reload.updated_at
      before_b = @expense_b.reload.updated_at

      result = run_batch(processor, store)

      assert_not result.success
      assert_not_empty result.errors
      assert_empty graph.drafts
      assert_equal 0, Batch.count
      # Nothing at all was written, not just the status.
      assert_equal before_a, @expense_a.reload.updated_at
      assert_equal before_b, @expense_b.reload.updated_at
      assert_equal Status::APPROVED, @expense_a.status
      assert_equal Status::APPROVED, @expense_b.status
    end

    test "an empty batch reports an error and touches nothing" do
      processor, = build_scenario
      result = processor.process(expenses: [], bacs_date: Date.new(2026, 5, 13),
                                 sender_name: "F", eusa_recipient: "finance@eusa.ed.ac.uk")

      assert_not result.success
      assert_includes result.errors, "No expenses in batch."
    end

    test "skips producers already notified for this (reopened) batch" do
      processor, store, graph = build_scenario(expenses: -> { })
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
      processor, store, graph = build_scenario(expenses: -> { })
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
      assert_includes alice_mail[:html], "Hi Alice,", "the payee is greeted by name"
      assert_includes alice_mail[:html], "Fake blood"
      assert_includes alice_mail[:html], "Face paint"
      assert_includes alice_mail[:html], "£20.00", "the total sums both of Alice's expenses"

      bob_mail = graph.send_mails.find { |mail| Array(mail[:to]) == [ "bob@example.com" ] }
      assert_includes bob_mail[:subject], "1 expense submitted for payment"

      assert alice1.reload.producer_notified
      assert alice2.reload.producer_notified,
             "both of Alice's expenses are stamped, not just one per notification"
    end

    test "a payee whose notification send fails is not stamped producer_notified" do
      processor, store, graph = build_scenario
      graph.fail_send_to = [ "alice@example.com" ] # Bob's send still succeeds

      result = run_batch(processor, store)

      assert result.success, result.errors.inspect
      assert(result.errors.any? { |e| e.include?("Producer notification failed for alice@example.com") })
      # Alice stays un-notified, so a rebuild re-notifies her.
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
