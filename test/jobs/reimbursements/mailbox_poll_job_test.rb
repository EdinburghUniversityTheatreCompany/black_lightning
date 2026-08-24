require "test_helper"

module Reimbursements
  class MailboxPollJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Interface-compatible stand-in for MailboxClient recording replies/moves.
    # Models the real idempotency guarantee: mark_read hides the message from
    # unread_messages, so a message read once is never re-processed even if the
    # (best-effort) move fails. Toggles let a step fail like Graph would.
    class FakeMailbox
      attr_reader :replies, :moves, :reads
      attr_accessor :fail_mark_read, :fail_move

      def initialize(messages: [], attachments: {})
        @messages = messages
        @attachments = attachments
        @replies = []
        @moves = []
        @reads = []
        @read_ids = []
      end

      def unread_messages
        @messages.reject { |message| @read_ids.include?(message.id) }
      end

      def attachments(message_id)
        @attachments.fetch(message_id, [])
      end

      def reply(message_id, html:)
        @replies << [ message_id, html ]
      end

      def mark_read(message_id)
        raise MailboxClient::Error, "isRead patch failed" if fail_mark_read

        @read_ids << message_id
        @reads << message_id
      end

      def move(message_id, folder)
        raise MailboxClient::Error, "move failed" if fail_move

        @moves << [ message_id, folder ]
      end

      def mark_read_and_move(message_id, folder)
        move(message_id, folder)
        mark_read(message_id)
      end
    end

    PDF_ATTACHMENT = { filename: "receipt.pdf", content_type: "application/pdf", bytes: "PDF" }.freeze

    def inbound_message(id: "msg1", from: "pat@example.com", subject: "Taxi receipt")
      MailboxClient::Message.new(id: id, from_address: from, subject: subject,
                                 body_text: "receipt attached")
    end

    def setup_job(messages:, attachments: {})
      ENV["REIMBURSEMENTS_AZURE_TENANT_ID"] = "t"
      ENV["REIMBURSEMENTS_AZURE_CLIENT_ID"] = "c"
      ENV["REIMBURSEMENTS_AZURE_CLIENT_SECRET"] = "s"

      @person = create_reimbursements_person(name: "Pat Producer", email: "pat@example.com")
      @budget = create_reimbursements_budget(name: "Props", active: true)
      @store = DatabaseStore.new
      @mailbox = FakeMailbox.new(messages: messages, attachments: attachments)
      # One cost centre (the fringe fixture); the builder receives it and returns
      # the fake mailbox for it. The multi-cost-centre test overrides this.
      MailboxPollJob.mailbox_builder = ->(_cost_centre) { @mailbox }
      MailboxPollJob.store_builder = -> { @store }
    end

    teardown do
      %w[REIMBURSEMENTS_AZURE_TENANT_ID REIMBURSEMENTS_AZURE_CLIENT_ID
         REIMBURSEMENTS_AZURE_CLIENT_SECRET].each { |key| ENV.delete(key) }
      MailboxPollJob.mailbox_builder =
        ->(cost_centre) { MailboxClient.new(mailbox: cost_centre.receive_mailbox) }
      MailboxPollJob.store_builder = -> { Reimbursements.build_store }
      Rails.cache.delete(GraphAuthAlert::CACHE_KEY)
      Rails.cache.delete_matched("reimbursements/mailbox-sender-count/*")
      Rails.cache.delete_matched("reimbursements/mailbox-sender-counted/*")
    end

    test "skips entirely when graph credentials are not configured" do
      setup_job(messages: [ inbound_message ])
      ENV.delete("REIMBURSEMENTS_AZURE_CLIENT_SECRET")

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies
    end

    test "no-ops without touching the mailbox when outbound is disabled" do
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])
      original = ENV.delete("REIMBURSEMENTS_ENABLE_OUTBOUND")

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies, "outbound disabled -> the mailbox is never polled or replied to"
      assert_empty @mailbox.moves
      assert_empty @mailbox.reads
      assert_equal 0, Expense.count
    ensure
      ENV["REIMBURSEMENTS_ENABLE_OUTBOUND"] = original if original
    end

    test "unknown sender gets a not-recognised reply and lands in rejected" do
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])

      MailboxPollJob.perform_now

      assert_equal 1, @mailbox.replies.size
      assert_match(/isn't in our submitter list/, @mailbox.replies.first.last)
      assert_includes @mailbox.replies.first.last, "<p>Hi,</p>",
                      "no matched person, so there is no name to greet"
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
      assert_equal 0, Expense.count
    end

    # The reply is written in the name of the cost centre whose mailbox the
    # message arrived on. A termtime submitter told to write to the Fringe's
    # finance address emails a team that can't help them.
    test "the automated reply names the cost centre whose mailbox it came from" do
      termtime = CostCentre.create!(key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "termtime@bedlamtheatre.co.uk", send_mailbox: "termtime@bedlamtheatre.co.uk")
      CostCentre.where.not(id: termtime.id).destroy_all
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])

      MailboxPollJob.perform_now

      reply = @mailbox.replies.sole.last
      assert_includes reply, "If you're part of Bedlam Termtime,"
      assert_includes reply, "Contact termtime@bedlamtheatre.co.uk."
      assert_includes reply, "Bedlam Termtime finance (automated reply)"
      assert_not_includes reply, "Fringe"
    end

    test "a move failure on the reject path leaves the message unread for retry, not stuck unfiled" do
      # mark_read_and_move moves BEFORE marking read specifically so a move
      # failure here (no expense created on this path) leaves the message
      # unread and safe to retry, rather than marked-read-but-never-filed.
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
      setup_job(messages: [ inbound_message(id: "msgNdr", from: "mailer-daemon@example.com"),
                            inbound_message(id: "msgNoReply", from: "no-reply@shop.example") ])

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies
      assert_equal [ [ "msgNdr", :rejected ], [ "msgNoReply", :rejected ] ], @mailbox.moves
    end

    test "a message with a blank from-address is treated as automated, not crashed on" do
      setup_job(messages: [ inbound_message(id: "msgBlank", from: "") ])

      assert_nothing_raised { MailboxPollJob.perform_now }

      assert_empty @mailbox.replies
      assert_equal [ [ "msgBlank", :rejected ] ], @mailbox.moves
    end

    # Real PNG bytes, not a stand-in string: an inline image now has to survive
    # ReceiptIntake's metadata strip, which decodes it.
    test "processes a pasted-in-body receipt (inline image)" do
      pasted = { filename: "pasted-receipt.png", content_type: "image/png",
                 bytes: File.binread(Rails.root.join("test/fixtures/files/renderable_receipt.png")) }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ pasted ] })

      MailboxPollJob.perform_now

      assert_equal 1, Expense.sole.receipt_files.count
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    test "known sender with a receipt gets a blank draft expense and a portal link" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      expense = Expense.sole
      assert_equal Status::DRAFT, expense.status
      assert_equal @person, expense.person
      # Only the subject seeds the description; amount/budget/reference are left
      # blank for the submitter to complete in the portal.
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
      # The move to Processed is gated on attach succeeding: a partially-
      # attached draft stays visible in the Inbox as a signal something needs
      # manual follow-up, rather than being filed away looking identical to a
      # fully successful run. The reply must still go out — the submitter is
      # waiting on their portal link regardless of the attach outcome.
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
      @mailbox.define_singleton_method(:reply) { |*| raise MailboxClient::Error, "reply failed" }

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

    test "an attachment with nil bytes is skipped, not crashed on" do
      nil_bytes = { filename: "broken.pdf", content_type: "application/pdf", bytes: nil }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ nil_bytes ] })

      assert_nothing_raised { MailboxPollJob.perform_now }

      assert_equal 0, Expense.count, "a broken attachment must not mint an expense"
      assert_match(/no usable receipt/, @mailbox.replies.first.last)
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
    end

    test "an attachment over the 5MB receipt limit is skipped, not attached" do
      oversized = { filename: "receipt.pdf", content_type: "application/pdf",
                   bytes: "a" * (ExpenseForm::MAX_RECEIPT_BYTES + 1) }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ oversized ] })

      MailboxPollJob.perform_now

      assert_equal 0, Expense.count, "an oversized attachment must not mint an expense"
      assert_match(/no usable receipt/, @mailbox.replies.first.last)
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
    end

    # Emailing an iPhone photo to the shared mailbox is a likely route in, so
    # email-in converts too: the draft carries a JPEG, not the HEIC.
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

    # A damaged photo must not raise inside the poll (that would leave the
    # message unread and reprocessed forever); it just isn't a usable receipt,
    # so the sender gets the existing "please attach the receipt" reply.
    test "an emailed HEIC that can't be decoded falls back to the missing-receipt reply" do
      broken = { filename: "IMG_9.HEIC", content_type: "image/heic",
                bytes: File.binread(Rails.root.join("test/fixtures/files/truncated_receipt.heic")) }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ broken ] })

      assert_nothing_raised { MailboxPollJob.perform_now }

      assert_equal 0, Expense.count, "an unreadable photo must not mint an expense"
      assert_match(/no usable receipt/, @mailbox.replies.first.last)
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
    end

    test "an attachment whose content isn't an allowed receipt type is skipped" do
      not_a_receipt = { filename: "notes.txt", content_type: "text/plain", bytes: "just some plain text notes" }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ not_a_receipt ] })

      MailboxPollJob.perform_now

      assert_equal 0, Expense.count, "a disallowed content type must not mint an expense"
      assert_match(/no usable receipt/, @mailbox.replies.first.last)
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
    end

    test "a failing message is left unread and others still process" do
      broken = inbound_message(id: "msgBoom")
      fine = inbound_message(id: "msg1")
      setup_job(messages: [ broken, fine ],
                attachments: { "msg1" => [ PDF_ATTACHMENT ], "msgBoom" => [ PDF_ATTACHMENT ] })
      original = @store.method(:create_expense!)
      calls = 0
      @store.define_singleton_method(:create_expense!) do |attrs|
        calls += 1
        raise "boom" if calls == 1

        original.call(attrs)
      end

      MailboxPollJob.perform_now

      assert_equal 1, Expense.count
      moved_ids = @mailbox.moves.map(&:first)
      assert_includes moved_ids, "msg1"
      assert_not_includes moved_ids, "msgBoom"
    end

    test "a message retried across poll cycles after a downstream failure counts once toward the sender's daily limit" do
      # A message left unread by a downstream failure (a data-layer blip, not a
      # sender problem) gets reprocessed every cycle until it succeeds — that
      # must not inflate one real email into many against the sender's tally,
      # or a transient outage could get a legitimate sender rate-limited.
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @store.define_singleton_method(:create_expense!) { |*| raise "boom" }

      3.times { MailboxPollJob.perform_now }

      count_key = "reimbursements/mailbox-sender-count/pat@example.com/#{Date.current}"
      assert_equal 1, Rails.cache.read(count_key)
    end

    test "polls each cost centre on its own receive mailbox" do
      termtime = CostCentre.create!(key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "termtime@bedlamtheatre.co.uk", send_mailbox: "termtime@bedlamtheatre.co.uk")

      setup_job(messages: [])
      fringe_mailbox = FakeMailbox.new(messages: [ inbound_message(id: "msgFringe") ],
                                       attachments: { "msgFringe" => [ PDF_ATTACHMENT ] })
      termtime_mailbox = FakeMailbox.new(messages: [ inbound_message(id: "msgTerm") ],
                                         attachments: { "msgTerm" => [ PDF_ATTACHMENT ] })
      by_mailbox = { "reimbursements@bedlamfringe.co.uk" => fringe_mailbox,
                     "termtime@bedlamtheatre.co.uk" => termtime_mailbox }
      polled = []
      MailboxPollJob.mailbox_builder = lambda do |cost_centre|
        polled << cost_centre.receive_mailbox
        by_mailbox.fetch(cost_centre.receive_mailbox)
      end

      MailboxPollJob.perform_now

      assert_includes polled, "reimbursements@bedlamfringe.co.uk"
      assert_includes polled, termtime.receive_mailbox
      assert_equal [ [ "msgFringe", :processed ] ], fringe_mailbox.moves
      assert_equal [ [ "msgTerm", :processed ] ], termtime_mailbox.moves
      assert_equal 2, Expense.count, "an expense is drafted from each cost centre's inbox"
    end

    test "a generic failure polling one cost centre's mailbox doesn't stop the others being polled" do
      CostCentre.create!(key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
        receive_mailbox: "termtime@bedlamtheatre.co.uk", send_mailbox: "termtime@bedlamtheatre.co.uk")

      setup_job(messages: [])
      broken_mailbox = Object.new.tap do |m|
        def m.unread_messages
          raise Reimbursements::MailboxClient::Error, "Graph 503"
        end
      end
      termtime_mailbox = FakeMailbox.new(messages: [ inbound_message(id: "msgTerm") ],
                                         attachments: { "msgTerm" => [ PDF_ATTACHMENT ] })
      by_mailbox = { "reimbursements@bedlamfringe.co.uk" => broken_mailbox,
                     "termtime@bedlamtheatre.co.uk" => termtime_mailbox }
      MailboxPollJob.mailbox_builder = ->(cost_centre) { by_mailbox.fetch(cost_centre.receive_mailbox) }

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, notified.size, "the broken cost centre's failure is still reported"
      assert_equal [ [ "msgTerm", :processed ] ], termtime_mailbox.moves,
                   "the other cost centre must still be polled despite the first one's failure"
      assert_equal 1, Expense.count
    end

    test "a sender matching the cost centre's own receive mailbox is treated as automated" do
      own = CostCentre.default.receive_mailbox
      setup_job(messages: [ inbound_message(id: "msgLoop", from: own) ],
                attachments: { "msgLoop" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies, "no reply to a message from our own mailbox (loop guard)"
      assert_equal [ [ "msgLoop", :rejected ] ], @mailbox.moves
      assert_equal 0, Expense.count
    end

    test "a known sender well under the daily message cap is unaffected" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      assert_equal 1, Expense.count
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
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
        raise MailboxClient::AuthError, "AADSTS7000222: client secret expired"
      end

      assert_emails 1 do
        MailboxPollJob.perform_now
        MailboxPollJob.perform_now
      end
      assert_match(/authentication is failing/, ActionMailer::Base.deliveries.last.subject)
    end

    # --- Idempotency key (source_message_id) -------------------------------

    test "stamps the source message id on the created draft" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      expense = Expense.find_by!(source_message_id: "msg1")
      assert_equal Status::DRAFT, expense.status
      assert_equal @person, expense.person
      assert_equal 1, expense.receipt_files.count
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    test "an already-seen message whose earlier cycle died before the attach is finished, not duplicated" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      # The earlier cycle created the expense (stamping the message id) but
      # crashed before attach/reply — the receipt-less draft must not be
      # filed away receipt-less with the sender never told.
      orphan = Expense.create!(status: Status::DRAFT, person: @person, source_message_id: "msg1")

      assert_no_difference -> { Expense.count } do
        MailboxPollJob.perform_now
      end

      assert_equal 1, orphan.reload.receipt_files.count, "the missing receipt is attached on retry"
      assert_equal 1, @mailbox.replies.size, "the sender finally gets their portal link"
      assert_equal [ "msg1" ], @mailbox.reads
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    # --- Vanished mailbox messages (Graph 404 ErrorItemNotFound) -----------

    # Drives the REAL MailboxClient (not the FakeMailbox) over FakeHttp so the
    # 404 swallowing in MailboxClient#mark_read/#move/#reply is exercised end to
    # end: a message handled or deleted by hand in Outlook between the poll's
    # listing and the mark_read PATCH is nothing to alert about.
    test "a message whose mark_read 404s (vanished from the mailbox) doesn't abort the poll or alert" do
      setup_job(messages: [])
      Rails.cache.delete_matched("reimbursements/graph-folder/*")

      def raw_unknown(id, from)
        { id: id, subject: "Receipt", bodyPreview: "see attached",
          from: { emailAddress: { address: from } } }
      end
      item_not_found = { error: { code: "ErrorItemNotFound",
                                  message: "The specified object was not found in the store." } }.to_json
      http = FakeHttp.new([
        [ 200, { access_token: "tok-1", expires_in: 3600 }.to_json ],                 # token
        [ 200, { value: [ raw_unknown("msgGone", "stranger1@example.com"),
                          raw_unknown("msgOk", "stranger2@example.com") ] }.to_json ], # unread list
        [ 202, "" ],                                                                   # reply msgGone
        [ 200, { value: [ { id: "fld-rejected" } ] }.to_json ],                        # folder lookup
        [ 201, { id: "moved" }.to_json ],                                              # move msgGone
        [ 404, item_not_found ],                                                        # mark_read msgGone -> 404
        [ 404, item_not_found ],                                                        # re-GET confirms it IS gone
        [ 202, "" ],                                                                   # reply msgOk
        [ 201, { id: "moved2" }.to_json ],                                             # move msgOk (folder cached)
        [ 200, "" ]                                                                    # mark_read msgOk
      ])
      MailboxPollJob.mailbox_builder = lambda do |cost_centre|
        MailboxClient.new(mailbox: cost_centre.receive_mailbox, http: http,
                          clock: -> { Time.zone.local(2026, 7, 9, 12) })
      end

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_empty notified, "a vanished message (404) must not raise a Honeybadger alert"
      patched = http.requests.select { |r| r.method.to_s == "patch" }.map(&:uri)
      assert(patched.any? { |uri| uri.include?("messages/msgOk") },
             "the poll must continue past the vanished message and mark the next one read")
      assert_equal 0, Expense.count
    ensure
      Rails.cache.delete_matched("reimbursements/graph-folder/*")
    end

    # Exchange CHANGES a message's id when the message is moved, so a mark_read
    # 404 can mean "still in the mailbox, still unread, under a new id". A
    # blanket 404 swallow turns that into silence: the expense is created,
    # mark_read reports SUCCESS, the sender is never told their claim arrived,
    # and no Honeybadger notice or duplicate_risk flag says so.
    #
    # Drives the REAL MailboxClient over FakeHttp, like the confirmed-gone test
    # above, so the difference between the two is only what the confirmation GET
    # answers.
    test "a mark_read 404 on a message that still exists flags duplicate_risk loudly" do
      setup_job(messages: [])
      Rails.cache.delete_matched("reimbursements/graph-folder/*")
      person = create_reimbursements_person(name: "Moved Morgan", email: "morgan@example.com")
      pdf = Base64.strict_encode64(PDF_ATTACHMENT[:bytes])
      item_not_found = { error: { code: "ErrorItemNotFound",
                                  message: "The specified object was not found in the store." } }.to_json
      http = FakeHttp.new([
        [ 200, { access_token: "tok-1", expires_in: 3600 }.to_json ],                  # token
        [ 200, { value: [ { id: "msgMoved", subject: "Receipt", bodyPreview: "see attached",
                            from: { emailAddress: { address: person.email } } } ] }.to_json ],
        [ 200, { value: [ { "@odata.type" => "#microsoft.graph.fileAttachment",
                            name: PDF_ATTACHMENT[:filename], contentType: PDF_ATTACHMENT[:content_type],
                            contentBytes: pdf } ] }.to_json ],                         # attachments
        [ 404, item_not_found ],                                                       # mark_read -> 404
        [ 200, { id: "msgMovedNewId" }.to_json ]                                       # ...but it IS still there
      ])
      MailboxPollJob.mailbox_builder = lambda do |cost_centre|
        MailboxClient.new(mailbox: cost_centre.receive_mailbox, http: http,
                          clock: -> { Time.zone.local(2026, 7, 9, 12) })
      end

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, Expense.count, "the expense was created before the mark_read attempt"
      assert_equal 1, notified.size, "a moved-but-present message must reach Honeybadger"
      assert notified.first.last.dig(:context, :duplicate_risk),
             "the duplicate_risk flag is the whole point of the loud path: #{notified.first.inspect}"
      # Nothing is attempted after the failed commit point: replying to or filing a
      # still-unread message would be acting on a message the next cycle will retry.
      assert_equal 5, http.requests.size,
                   "no reply and no move after mark_read failed: #{http.requests.map(&:uri).inspect}"
    ensure
      Rails.cache.delete_matched("reimbursements/graph-folder/*")
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
