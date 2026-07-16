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

    # Extractor stand-in returning a canned extraction.
    class FakeExtractor
      def initialize(extraction)
        @extraction = extraction
      end

      def extract(**)
        @extraction
      end
    end

    PDF_ATTACHMENT = { filename: "receipt.pdf", content_type: "application/pdf", bytes: "PDF" }.freeze

    def inbound_message(id: "msg1", from: "pat@example.com", subject: "Taxi receipt")
      MailboxClient::Message.new(id: id, from_address: from, subject: subject,
                                 body_text: "receipt attached")
    end

    def happy_extraction
      Extractor::Extraction.new(
        merchant: "City Cabs", total_amount: BigDecimal("18.00"), vat_amount: BigDecimal("3.00"),
        vat_itemised: true, suggested_description: "Taxi to venue",
        suggested_budget_record_id: "recBud1", suggested_payment_reference: "CITYCABS PAT"
      )
    end

    def setup_job(messages:, attachments: {}, extraction: nil)
      ENV["REIMBURSEMENTS_AZURE_TENANT_ID"] = "t"
      ENV["REIMBURSEMENTS_AZURE_CLIENT_ID"] = "c"
      ENV["REIMBURSEMENTS_AZURE_CLIENT_SECRET"] = "s"

      @store, @client = build_fake_store(people: [ airtable_person_record ],
                                         budgets: [ airtable_budget_record ])
      @mailbox = FakeMailbox.new(messages: messages, attachments: attachments)
      # One cost centre (the fringe fixture); the builder receives it and returns
      # the fake mailbox for it. The multi-cost-centre test overrides this.
      MailboxPollJob.mailbox_builder = ->(_cost_centre) { @mailbox }
      MailboxPollJob.store_builder = -> { @store }
      MailboxPollJob.extractor_builder = -> { FakeExtractor.new(extraction || happy_extraction) }
    end

    teardown do
      %w[REIMBURSEMENTS_AZURE_TENANT_ID REIMBURSEMENTS_AZURE_CLIENT_ID
         REIMBURSEMENTS_AZURE_CLIENT_SECRET].each { |key| ENV.delete(key) }
      MailboxPollJob.mailbox_builder =
        ->(cost_centre) { MailboxClient.new(mailbox: cost_centre.receive_mailbox) }
      MailboxPollJob.store_builder = -> { Store.new }
      MailboxPollJob.extractor_builder = -> { Extractor.new }
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

    test "unknown sender gets a not-recognised reply and lands in rejected" do
      setup_job(messages: [ inbound_message(from: "stranger@example.com") ])

      MailboxPollJob.perform_now

      assert_equal 1, @mailbox.replies.size
      assert_match(/isn't in our submitter list/, @mailbox.replies.first.last)
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
      assert_empty @client.created
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
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
      assert_empty @client.created
    end

    test "automated senders get no reply (mail-loop guard)" do
      setup_job(messages: [ inbound_message(id: "msgNdr", from: "mailer-daemon@example.com"),
                            inbound_message(id: "msgNoReply", from: "no-reply@shop.example") ])

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies
      assert_equal [ [ "msgNdr", :rejected ], [ "msgNoReply", :rejected ] ], @mailbox.moves
    end

    test "processes a pasted-in-body receipt (inline image)" do
      pasted = { filename: "pasted-receipt.png", content_type: "image/png", bytes: "BIGPNG" }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ pasted ] })

      MailboxPollJob.perform_now

      assert_equal 1, @client.created.size
      assert_equal 1, @client.uploads.size
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    test "known sender with a receipt gets a draft expense and a portal link" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      _table, fields = @client.created.sole
      f = ReimbursementsTestHelpers::FIELD_IDS[:expenses]
      assert_equal "Draft", fields[f[:status]]
      assert_equal [ "recPer1" ], fields[f[:payee]]
      assert_equal [ "recBud1" ], fields[f[:budget]]
      assert_in_delta 18.0, fields[f[:amount]]
      assert_in_delta 15.0, fields[f[:amount_excl_vat]]
      assert_equal "Taxi to venue", fields[f[:description]]

      assert_equal 1, @client.uploads.size
      reply_html = @mailbox.replies.sole.last
      assert_includes reply_html, "/admin/reimbursements/expenses/recNew1/edit"
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
      @client.fail_uploads = true

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, @client.created.size
      assert_includes @mailbox.reads, "msg1", "marked read regardless, so it's never reprocessed"
      assert_equal 1, @mailbox.replies.size, "the submitter must still get their portal link"
      assert_empty @mailbox.moves, "a partially-attached draft stays in the Inbox, not filed away"
      assert_equal 1, notified.size, "the attach failure must reach Honeybadger"
    end

    test "a reply failure does not prevent the receipt attach or block the move" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @mailbox.define_singleton_method(:reply) { |*| raise MailboxClient::Error, "reply failed" }

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, @client.created.size
      assert_equal 1, @client.uploads.size, "the attach must not be skipped just because the reply will fail"
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves,
                   "attach succeeded, so the move must still happen despite the reply failing"
      assert_equal 1, notified.size
    end

    test "a move failure after marking read does not re-create on the next poll" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @mailbox.fail_move = true

      MailboxPollJob.perform_now
      MailboxPollJob.perform_now

      assert_equal 1, @client.created.size, "a read message must not be re-processed into a duplicate"
      assert_includes @mailbox.reads, "msg1", "marking read is the idempotency step and must happen"
      assert_empty @mailbox.moves, "the move failed, but the message is already read so it is safe"
    end

    test "a failed isRead after creating the expense is surfaced, not swallowed" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @mailbox.fail_mark_read = true

      notified = capture_honeybadger_notices { MailboxPollJob.perform_now }

      assert_equal 1, @client.created.size
      assert_equal 1, notified.size, "the isRead failure must reach Honeybadger"
      assert notified.first.last.dig(:context, :duplicate_risk),
             "a possible duplicate must be flagged so an operator can check"
      assert_empty @mailbox.moves
    end

    test "an attachment with nil bytes is skipped, not crashed on" do
      nil_bytes = { filename: "broken.pdf", content_type: "application/pdf", bytes: nil }
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ nil_bytes ] })

      assert_nothing_raised { MailboxPollJob.perform_now }

      assert_empty @client.created, "a broken attachment must not mint an expense"
      assert_match(/no usable receipt/, @mailbox.replies.first.last)
      assert_equal [ [ "msg1", :rejected ] ], @mailbox.moves
    end

    test "extraction failure still creates the expense with subject and receipt only" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] },
                extraction: Extractor::Extraction.new(error: "gemini down"))

      MailboxPollJob.perform_now

      _table, fields = @client.created.sole
      f = ReimbursementsTestHelpers::FIELD_IDS[:expenses]
      assert_equal "Taxi receipt", fields[f[:description]], "description falls back to the subject"
      assert_nil fields[f[:amount]]
      assert_nil fields[f[:budget]]
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
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
        raise Airtable::Error.new("boom", status: 500) if calls == 1

        original.call(attrs)
      end

      MailboxPollJob.perform_now

      assert_equal 1, @client.created.size
      moved_ids = @mailbox.moves.map(&:first)
      assert_includes moved_ids, "msg1"
      assert_not_includes moved_ids, "msgBoom"
    end

    test "a message retried across poll cycles after a downstream failure counts once toward the sender's daily limit" do
      # A message left unread by a downstream failure (an Airtable blip, not a
      # sender problem) gets reprocessed every cycle until it succeeds — that
      # must not inflate one real email into many against the sender's tally,
      # or a transient outage could get a legitimate sender rate-limited.
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @store.define_singleton_method(:create_expense!) { |*| raise Airtable::Error.new("boom", status: 500) }

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
      assert_equal 2, @client.created.size, "an expense is drafted from each cost centre's inbox"
    end

    test "a generic failure polling one cost centre's mailbox doesn't stop the others being polled" do
      termtime = CostCentre.create!(key: "termtime", name: "Bedlam Termtime", eusa_code: "BED",
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
      assert_equal 1, @client.created.size
    end

    test "a sender matching the cost centre's own receive mailbox is treated as automated" do
      own = CostCentre.default.receive_mailbox
      setup_job(messages: [ inbound_message(id: "msgLoop", from: own) ],
                attachments: { "msgLoop" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies, "no reply to a message from our own mailbox (loop guard)"
      assert_equal [ [ "msgLoop", :rejected ] ], @mailbox.moves
      assert_empty @client.created
    end

    test "a known sender well under the daily message cap is unaffected" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      assert_equal 1, @client.created.size
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves
    end

    test "a known sender over the daily message cap is rejected, not silently drafted forever" do
      key = "reimbursements/mailbox-sender-count/pat@example.com/#{Date.current}"
      Rails.cache.write(key, MailboxPollJob::MAX_MESSAGES_PER_SENDER_PER_DAY, expires_in: 1.day)
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      assert_empty @client.created, "a compromised/spoofed sender must not mint unbounded drafts"
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
  end
end
