require "test_helper"

module Reimbursements
  class MailboxPollJobTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    # Interface-compatible stand-in for MailboxClient recording replies/moves.
    class FakeMailbox
      attr_reader :replies, :moves

      def initialize(messages: [], attachments: {})
        @messages = messages
        @attachments = attachments
        @replies = []
        @moves = []
      end

      def unread_messages
        @messages
      end

      def attachments(message_id)
        @attachments.fetch(message_id, [])
      end

      def reply(message_id, html:)
        @replies << [ message_id, html ]
      end

      def mark_read_and_move(message_id, folder)
        @moves << [ message_id, folder ]
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
      Rails.cache.delete(MailboxPollJob::AUTH_ALERT_CACHE_KEY)
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

    test "a post-create failure still moves the message (no duplicate minting)" do
      setup_job(messages: [ inbound_message ], attachments: { "msg1" => [ PDF_ATTACHMENT ] })
      @client.fail_uploads = true

      MailboxPollJob.perform_now

      assert_equal 1, @client.created.size
      assert_equal [ [ "msg1", :processed ] ], @mailbox.moves,
                   "message must leave the inbox once the expense exists"
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

    test "a sender matching the cost centre's own receive mailbox is treated as automated" do
      own = CostCentre.default.receive_mailbox
      setup_job(messages: [ inbound_message(id: "msgLoop", from: own) ],
                attachments: { "msgLoop" => [ PDF_ATTACHMENT ] })

      MailboxPollJob.perform_now

      assert_empty @mailbox.replies, "no reply to a message from our own mailbox (loop guard)"
      assert_equal [ [ "msgLoop", :rejected ] ], @mailbox.moves
      assert_empty @client.created
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
