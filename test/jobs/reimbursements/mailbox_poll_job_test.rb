require "test_helper"

module Reimbursements
  class MailboxPollJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Stand-in for MailboxClient recording replies and moves. mark_read hides the message from
    # unread_messages, as the real idempotency guarantee does, even if the best-effort move
    # fails. Toggles make a step fail like Graph would.
    class FakeMailbox
      attr_reader :replies, :moves, :reads
      attr_accessor :fail_mark_read, :fail_move

      def initialize(messages: [], attachments: {})
        @messages = messages
        @attachments = attachments
        @replies = []
        @moves = []
        @reads = []
      end

      def unread_messages
        @messages.reject { |message| @reads.include?(message.id) }
      end

      def attachments(message_id)
        @attachments.fetch(message_id, [])
      end

      def reply(message_id, html:)
        @replies << [ message_id, html ]
      end

      def mark_read(message_id)
        raise GraphAuth::Error, "isRead patch failed" if fail_mark_read

        @reads << message_id
      end

      def move(message_id, folder)
        raise GraphAuth::Error, "move failed" if fail_move

        @moves << [ message_id, folder ]
      end

      def mark_read_and_move(message_id, folder)
        move(message_id, folder)
        mark_read(message_id)
      end
    end

    PDF_ATTACHMENT = { filename: "receipt.pdf", content_type: "application/pdf", bytes: "PDF" }.freeze

    def inbound_message(id: "msg1", from: "pat@example.com", subject: "Taxi receipt")
      Graph::MailboxClient::Message.new(id: id, from_address: from, subject: subject,
                                 body_text: "receipt attached")
    end

    setup do
      @original_builders = [ MailboxPollJob.mailbox_builder, MailboxPollJob.store_builder ]
    end

    def setup_job(messages:, attachments: {})
      ENV["REIMBURSEMENTS_AZURE_TENANT_ID"] = "t"
      ENV["REIMBURSEMENTS_AZURE_CLIENT_ID"] = "c"
      ENV["REIMBURSEMENTS_AZURE_CLIENT_SECRET"] = "s"

      @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com")
      @budget = create_reimbursements_budget(name: "Props", active: true)
      @store = DatabaseStore.new
      @mailbox = FakeMailbox.new(messages: messages, attachments: attachments)
      # One cost centre (the fringe fixture); the multi-cost-centre test overrides this.
      MailboxPollJob.mailbox_builder = ->(_cost_centre) { @mailbox }
      MailboxPollJob.store_builder = -> { @store }
    end

    teardown do
      %w[REIMBURSEMENTS_AZURE_TENANT_ID REIMBURSEMENTS_AZURE_CLIENT_ID
         REIMBURSEMENTS_AZURE_CLIENT_SECRET].each { |key| ENV.delete(key) }
      MailboxPollJob.mailbox_builder, MailboxPollJob.store_builder = @original_builders
      Rails.cache.delete(GraphAuthAlert::CACHE_KEY)
      Rails.cache.delete_matched("reimbursements/mailbox-sender-count/*")
      Rails.cache.delete_matched("reimbursements/mailbox-sender-counted/*")
      Rails.cache.delete_matched("reimbursements/graph-folder/*")
    end

    test "skips entirely when graph credentials are not configured" do
      setup_job(messages: [ inbound_message ])
      ENV.delete("REIMBURSEMENTS_AZURE_CLIENT_SECRET")

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies
    end

    test "no-ops without touching the mailbox when outbound is disabled" do
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])

      without_outbound { MailboxPollJob.perform_now }

      assert_empty @mailbox.replies, "outbound disabled -> the mailbox is never polled or replied to"
      assert_empty @mailbox.moves
      assert_empty @mailbox.reads
      assert_equal 0, Expense.count
    end

    # The reply names the cost centre whose mailbox the message arrived on, not the Fringe's.
    test "the automated reply names the cost centre whose mailbox it came from" do
      termtime = create_second_reimbursements_cost_centre
      CostCentre.where.not(id: termtime.id).destroy_all
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])

      MailboxPollJob.perform_now

      reply = @mailbox.replies.sole.last
      assert_match(/isn't in our submitter list/, reply)
      assert_includes reply, "<p>Hi,</p>", "no matched person, so there is no name to greet"
      assert_includes reply, "If you're part of Bedlam Termtime,"
      assert_includes reply, "Contact termtime-finance@example.invalid."
      assert_not_includes reply, "Contact #{termtime.receive_mailbox}", "never the polled mailbox"
      assert_includes reply, "Bedlam Termtime finance (automated reply)"
      assert_not_includes reply, "Fringe"
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
      assert_equal 0, Expense.count
    end

    test "the reply names no contact rather than the polled mailbox itself" do
      CostCentre.default.update_columns(notification_email: nil)
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])

      MailboxPollJob.perform_now

      assert_not_includes @mailbox.replies.sole.last, "Questions?"
    end

    test "a move failure on the reject path leaves the message unread for retry, not stuck unfiled" do
      # Moves BEFORE marking read, so a move failure leaves the message unread and retryable.
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])
      @mailbox.fail_move = true

      capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, @mailbox.replies.size, "the reply is sent before the move is even attempted"
      assert_empty @mailbox.reads, "must not be marked read when the move failed"
      assert_equal [ "msg1" ], @mailbox.unread_messages.map(&:id), "still eligible for retry next cycle"
    end

    test "known sender without usable attachments is asked for the receipt" do
      setup_job(messages: [ inbound_message ])

      MailboxPollJob.perform_now

      assert_match(/no usable receipt/, @mailbox.replies.first.last)
      assert_includes @mailbox.replies.first.last, "Hi Pat,",
                      "the sender was matched, so greet Pat Producer by first name"
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
      assert_equal 0, Expense.count
    end

    # The heredocs don't escape, and User#first_name is self-service editable.
    test "a payee name containing markup is escaped into the reply" do
      setup_job(messages: [ inbound_message(from: "mallory@example.com") ])
      create_reimbursements_person(name: "<script>alert(1)</script> Mallory",
                                   email: "mallory@example.com")

      MailboxPollJob.perform_now

      reply = @mailbox.replies.sole.last
      assert_not_includes reply, "<script>"
      assert_includes reply, "Hi &lt;script&gt;alert(1)&lt;/script&gt;,"
    end

    test "automated senders get no reply (mail-loop guard)" do
      own = CostCentre.default.receive_mailbox
      setup_job(messages: [ inbound_message(id: "msgNdr", from: "mailer-daemon@example.com"),
                            inbound_message(id: "msgNoReply", from: "no-reply@shop.example"),
                            inbound_message(id: "msgBlank", from: ""),
                            inbound_message(id: "msgLoop", from: own) ],
                attachments: { "msgLoop" => [ PDF_ATTACHMENT ] })

      assert_nothing_raised { MailboxPollJob.perform_now }

      assert_empty @mailbox.replies
      assert_equal %w[msgNdr msgNoReply msgBlank msgLoop].map { |id| [ id, :rejected ] }, @mailbox.moves
      assert_equal 0, Expense.count, "even a message carrying a receipt is not drafted"
    end

    test "known sender with a receipt gets a blank draft expense and a portal link" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      expense = Expense.sole
      assert_equal Status::DRAFT, expense.status
      assert_equal @person, expense.person
      assert_equal "msg1", expense.source_message_id
      # Only the subject seeds the description; the rest is left for the submitter.
      assert_equal "Taxi receipt", expense.description, "the subject seeds the description"
      assert_nil expense.amount, "the amount is left for the portal"
      assert_nil expense.amount_excl_vat
      assert_nil expense.budget
      assert_nil expense.payment_reference

      assert_equal 1, expense.receipt_files.count
      reply_html = @mailbox.replies.sole.last
      assert_includes reply_html, "/admin/reimbursements/expenses/#{expense.record_id}/edit"
      assert_includes reply_html, "Hi Pat,", "the draft's payee is greeted by first name"
      assert_includes reply_html, "won't see the claim until you submit"
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    test "an attach failure still marks read and replies (no duplicate minting), but withholds the move" do
      # The move to Processed is gated on attach: a partly attached draft stays in the Inbox.
      # The reply still goes out, since the submitter is waiting on their link.
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @store.define_singleton_method(:attach_receipt!) { |*| raise "storage down" }

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, Expense.count
      assert_includes @mailbox.reads, "msg1", "marked read regardless, so it's never reprocessed"
      assert_equal 1, @mailbox.replies.size, "the submitter must still get their portal link"
      assert_empty @mailbox.moves, "a partially-attached draft stays in the Inbox, not filed away"
      assert_equal 1, notified.size, "the attach failure must reach Honeybadger"
    end

    test "a reply failure does not prevent the receipt attach or block the move" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @mailbox.define_singleton_method(:reply) { |*| raise GraphAuth::Error, "reply failed" }

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      expense = Expense.sole
      assert_equal 1, expense.receipt_files.count, "the attach must not be skipped just because the reply will fail"
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves,
                   "attach succeeded, so the move must still happen despite the reply failing"
      assert_equal 1, notified.size
    end

    test "a move failure after marking read does not re-create on the next poll" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @mailbox.fail_move = true

      MailboxPollJob.perform_now
      MailboxPollJob.perform_now

      assert_equal 1, Expense.count, "a read message must not be re-processed into a duplicate"
      assert_includes @mailbox.reads, "msg1", "marking read is the idempotency step and must happen"
      assert_empty @mailbox.moves, "the move failed, but the message is already read so it is safe"
    end

    test "a failed isRead after creating the expense is surfaced, not swallowed" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @mailbox.fail_mark_read = true

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, Expense.count
      assert_equal 1, notified.size, "the isRead failure must reach Honeybadger"
      assert notified.first.last.dig(:context, :duplicate_risk),
             "a possible duplicate must be flagged so an operator can check"
      assert_empty @mailbox.moves
    end

    # Email-in converts HEIC too: the draft carries a JPEG.
    test "an emailed HEIC photo is converted to a JPEG on the draft" do
      heic = { filename: "IMG_1234.HEIC", content_type: "image/heic",
              bytes: File.binread(Rails.root.join("test/fixtures/files/reimbursements_receipt.heic")) }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ heic ] })

      MailboxPollJob.perform_now

      receipt = Expense.sole.receipt_files.sole
      assert_equal "image/jpeg", receipt.content_type
      assert_equal "IMG_1234.jpg", receipt.filename.to_s
      assert_equal "image/jpeg", Marcel::MimeType.for(StringIO.new(receipt.download))
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    # None of these may raise inside the poll (the message would be reprocessed for ever): each is
    # just not a usable receipt. Why is ReceiptIntake's business, tested in receipt_intake_test.
    {
      "an attachment with nil bytes" =>
        -> { { filename: "broken.pdf", content_type: "application/pdf", bytes: nil } },
      "an attachment over the 5MB limit" =>
        -> { { filename: "receipt.pdf", content_type: "application/pdf", bytes: "a" * (ExpenseForm::MAX_RECEIPT_BYTES + 1) } },
      "an emailed HEIC that can't be decoded" =>
        -> { { filename: "IMG_9.HEIC", content_type: "image/heic", bytes: File.binread(Rails.root.join("test/fixtures/files/truncated_receipt.heic")) } },
      "an attachment of a disallowed content type" =>
        -> { { filename: "notes.txt", content_type: "text/plain", bytes: "just some plain text notes" } }
    }.each do |label, build|
      test "#{label} is not a usable receipt" do
        setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ build.call ] })

        assert_nothing_raised { MailboxPollJob.perform_now }

        assert_equal 0, Expense.count
        assert_match(/no usable receipt/, @mailbox.replies.sole.last)
        assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
      end
    end

    test "a failing message is left unread and others still process" do
      broken = inbound_message(id: "msgBoom")
      fine = inbound_message(id: "msg1")
      setup_job(messages: [ broken, fine ],
                attachments: { "msg1" => [ PDF_ATTACHMENT ], "msgBoom" => [ PDF_ATTACHMENT ] })
      original = @store.method(:create_expense!)
      @store.define_singleton_method(:create_expense!) do |attrs|
        attrs[:source_message_id] == "msgBoom" ? raise("boom") : original.call(attrs)
      end

      MailboxPollJob.perform_now

      assert_equal 1, Expense.count
      moved_ids = @mailbox.moves.map(&:first)
      assert_includes moved_ids, "msg1"
      assert_not_includes moved_ids, "msgBoom"
      assert_equal [ "msgBoom" ], @mailbox.unread_messages.map(&:id)
    end

    test "a message retried across poll cycles after a downstream failure counts once toward the sender's daily limit" do
      # A message left unread by a downstream failure is reprocessed every cycle; that must not
      # inflate the sender's tally.
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @store.define_singleton_method(:create_expense!) { |*| raise "boom" }

      3.times { MailboxPollJob.perform_now }

      count_key = "reimbursements/mailbox-sender-count/pat@example.com/#{Date.current}"
      assert_equal 1, Rails.cache.read(count_key)
    end

    test "polls each cost centre on its own receive mailbox" do
      termtime = create_second_reimbursements_cost_centre

      setup_job(messages: [])
      fringe_mailbox = FakeMailbox.new(messages: [ inbound_message(id: "msgFringe") ],
                                       attachments: { "msgFringe" => [ PDF_ATTACHMENT ] })
      termtime_mailbox = FakeMailbox.new(messages: [ inbound_message(id: "msgTerm") ],
                                         attachments: { "msgTerm" => [ PDF_ATTACHMENT ] })
      by_mailbox = { "reimbursements@bedlamfringe.co.uk" => fringe_mailbox,
                     termtime.receive_mailbox => termtime_mailbox }
      MailboxPollJob.mailbox_builder = ->(cost_centre) { by_mailbox.fetch(cost_centre.receive_mailbox) }

      MailboxPollJob.perform_now

      assert_equal [ [ "msgFringe", :processed ] ], fringe_mailbox.moves
      assert_equal [ [ "msgTerm", :processed ] ], termtime_mailbox.moves
      assert_equal 2, Expense.count, "an expense is drafted from each cost centre's inbox"
    end

    test "a generic failure polling one cost centre's mailbox doesn't stop the others being polled" do
      termtime = create_second_reimbursements_cost_centre

      setup_job(messages: [])
      broken_mailbox = Object.new.tap do |m|
        def m.unread_messages
          raise GraphAuth::Error, "Graph 503"
        end
      end
      termtime_mailbox = FakeMailbox.new(messages: [ inbound_message(id: "msgTerm") ],
                                         attachments: { "msgTerm" => [ PDF_ATTACHMENT ] })
      by_mailbox = { "reimbursements@bedlamfringe.co.uk" => broken_mailbox,
                     termtime.receive_mailbox => termtime_mailbox }
      MailboxPollJob.mailbox_builder = ->(cost_centre) { by_mailbox.fetch(cost_centre.receive_mailbox) }

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, notified.size, "the broken cost centre's failure is still reported"
      assert_equal [ [ "msgTerm", :processed ] ], termtime_mailbox.moves,
                   "the other cost centre must still be polled despite the first one's failure"
      assert_equal 1, Expense.count
    end

    test "a known sender over the daily message cap is rejected, not silently drafted forever" do
      key = "reimbursements/mailbox-sender-count/pat@example.com/#{Date.current}"
      Rails.cache.write(key, MailboxPollJob::MAX_MESSAGES_PER_SENDER_PER_DAY, expires_in: 1.day)
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      assert_equal 0, Expense.count, "a compromised/spoofed sender must not mint unbounded drafts"
      assert_match(/unusually high number/, @mailbox.replies.sole.last)
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
    ensure
      Rails.cache.delete(key)
    end

    test "auth failure alerts the IT subcommittee once per day" do
      setup_job(messages: [])
      @mailbox.define_singleton_method(:unread_messages) do
        raise GraphAuth::AuthError, "AADSTS7000222: client secret expired"
      end

      assert_emails 1 do
        MailboxPollJob.perform_now
        MailboxPollJob.perform_now
      end
      assert_match(/authentication is failing/, ActionMailer::Base.deliveries.last.subject)
    end

    test "an already-seen message whose earlier cycle died before the attach is finished, not duplicated" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      # An earlier cycle created the expense but crashed before attach/reply: the draft must not
      # be filed away receipt-less with the sender never told.
      orphan = Expense.create!(status: Status::DRAFT, person: @person, source_message_id: "msg1")

      assert_no_difference -> { Expense.count } do
        MailboxPollJob.perform_now
      end

      assert_equal 1, orphan.reload.receipt_files.count, "the missing receipt is attached on retry"
      assert_equal 1, @mailbox.replies.size, "the sender finally gets their portal link"
      assert_equal [ "msg1" ], @mailbox.reads
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    # Exchange changes a message's id on move, so a mark_read 404 can mean "still in the mailbox,
    # under a new id". Swallowing it would leave the sender un-replied with no Honeybadger notice
    # or duplicate_risk flag. Drives the REAL MailboxClient over FakeHttp.
    test "a mark_read 404 on a message that still exists flags duplicate_risk loudly" do
      setup_job(messages: [])
      person = create_reimbursements_person(name: "Moved Morgan", email: "morgan@example.com")
      pdf = Base64.strict_encode64(PDF_ATTACHMENT[:bytes])
      http = FakeHttp.new([
        [ 200, { access_token: "tok-1", expires_in: 3600 }.to_json ],                  # token
        [ 200, { value: [ { id: "msgMoved", subject: "Receipt", bodyPreview: "see attached",
                            from: { emailAddress: { address: person.email } } } ] }.to_json ],
        [ 200, { value: [ { "@odata.type" => "#microsoft.graph.fileAttachment",
                            name: PDF_ATTACHMENT[:filename], contentType: PDF_ATTACHMENT[:content_type],
                            contentBytes: pdf } ] }.to_json ],                         # attachments
        [ 404, GRAPH_ITEM_NOT_FOUND ],                                                 # mark_read -> 404
        [ 200, { id: "msgMovedNewId" }.to_json ]                                       # ...but it IS still there
      ])
      MailboxPollJob.mailbox_builder = lambda do |cost_centre|
        Graph::MailboxClient.new(mailbox: cost_centre.receive_mailbox, http: http,
                          clock: -> { Time.zone.local(2026, 7, 9, 12) })
      end

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, Expense.count, "the expense was created before the mark_read attempt"
      assert_equal 1, notified.size, "a moved-but-present message must reach Honeybadger"
      assert notified.first.last.dig(:context, :duplicate_risk),
             "the duplicate_risk flag is the whole point of the loud path: #{notified.first.inspect}"
      # Nothing is attempted after the failed commit point: the next cycle retries the unread message.
      assert_equal 5, http.requests.size,
                   "no reply and no move after mark_read failed: #{http.requests.map(&:uri).inspect}"
    end

    test "an already-seen message whose receipts are already attached is filed away silently" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      done = Expense.create!(status: Status::DRAFT, person: @person, source_message_id: "msg1")
      done.receipt_files.attach(io: StringIO.new(PDF_ATTACHMENT[:bytes]),
                                filename: PDF_ATTACHMENT[:filename],
                                content_type: PDF_ATTACHMENT[:content_type])

      assert_no_difference -> { Expense.count } do
        MailboxPollJob.perform_now
      end

      assert_equal 1, done.reload.receipt_files.count, "no duplicate attach"
      assert_empty @mailbox.replies, "the earlier cycle already replied — no double email"
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end
  end
end
