require "test_helper"

module Reimbursements
  class NotifierTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    Person = Struct.new(:name, :email, keyword_init: true)
    PaidExpense = Struct.new(:description, :amount, :auto_number, keyword_init: true)

    MAILBOX = "send@bedlamfringe.co.uk".freeze

    def build(**opts)
      graph = FakeGraphClient.new
      [ Notifier.new(mailbox: MAILBOX, graph: graph, **opts), graph ]
    end

    test "rejection sends from the mailbox with the payee, subject and rendered body" do
      notifier, graph = build

      notifier.rejection(to: "pat@example.com", payee_name: "Pat Producer", auto_number: 7,
                         amount: 12.5, budget_name: "Props", description: "Fake blood",
                         reason: "Receipt is missing the VAT breakdown.")

      mail = graph.send_mails.sole
      assert_equal MAILBOX, mail[:mailbox]
      assert_equal [ "pat@example.com" ], mail[:to]
      assert_match(/expense #7/i, mail[:subject])
      assert_match "Pat Producer", mail[:html]
      assert_match "Receipt is missing the VAT breakdown.", mail[:html]
      assert_match "12.50", mail[:html]
      assert_match "Props", mail[:html]
    end

    test "payment_confirmation addresses the payee and pluralises the subject" do
      notifier, graph = build
      person = Person.new(name: "Alice Producer", email: "alice@example.com")
      expenses = [ PaidExpense.new(description: "Props", amount: 5, auto_number: 1),
                   PaidExpense.new(description: "Set", amount: 8, auto_number: 2) ]

      notifier.payment_confirmation(to: person.email, person: person, expenses: expenses)

      mail = graph.send_mails.sole
      assert_equal [ "alice@example.com" ], mail[:to]
      assert_equal "EUSA has paid your expenses", mail[:subject]
      assert_match "Alice Producer", mail[:html]
      assert_match "Props", mail[:html]
      assert_match "Set", mail[:html]
    end

    test "producer_notification lists the payee's expenses and totals" do
      notifier, graph = build
      line_items = [ { amount: "12.50", budget_name: "Props", description: "Fake blood" },
                     { amount: "8.00", budget_name: "Props", description: "Brushes" } ]

      notifier.producer_notification(to: "alice@example.com", recipient_name: "Alice Producer",
                                     line_items: line_items, bacs_date: Date.new(2026, 5, 13), total: "20.50")

      mail = graph.send_mails.sole
      assert_equal "[Bedlam Fringe] 2 expenses submitted for payment", mail[:subject]
      assert_match "Hi Alice Producer,", mail[:html]
      assert_match "Fake blood", mail[:html]
      assert_match "20.50", mail[:html]
      assert_match "2026-05-13", mail[:html]
    end

    test "operator alerts render their bodies and carry the standard subjects" do
      notifier, graph = build
      recipients = [ "ops@bedlamfringe.co.uk" ]

      notifier.pending_reminder(recipients: recipients, run_date: "9 July 2026", threshold_days: 3,
                                rows: [ { auto_number: 7, payee_name: "Pat", amount: "12.50", age_days: 5 } ])
      notifier.manual_review(recipients: recipients, unblocked_count: 2, run_date: "9 July 2026",
                             next_run_day: "Tuesday 14 July",
                             issues: [ { auto_number: 3, payee_name: "Sam", amount: "40.00",
                                         reason: "AI review: amount mismatch" } ])
      notifier.approved_ready(recipients: recipients, total: "40.00", run_date: "9 July 2026",
                              expenses: [ { auto_number: 3, payee_name: "Sam", amount: "40.00",
                                            budget_name: "Props", description: "Paint" } ])
      notifier.batch_ready(recipients: recipients, total: "52.50", run_date: "9 July 2026",
                           draft_link: "https://outlook.example/draft-1",
                           expenses: [ { auto_number: 3, payee_name: "Sam", amount: "40.00",
                                         budget_name: "Props", description: "Paint" } ])
      notifier.failure(recipients: recipients, error_text: "SharePoint down", run_date: "9 July 2026")

      reminder, review, approved, ready, failure = graph.send_mails
      assert_equal recipients, reminder[:to]
      assert_match(/awaiting approval/, reminder[:subject])
      assert_match "5 day", reminder[:html]
      assert_match(/Manual review needed/, review[:subject])
      assert_match "amount mismatch", review[:html]
      assert_match "Tuesday 14 July", review[:html]
      # The ready-to-batch alert prompts Build Batch and carries NO draft link.
      assert_match(/ready to batch/, approved[:subject])
      assert_match "Build Batch", approved[:html]
      assert_no_match(/outlook\.example/, approved[:html])
      assert_match(/Draft ready/, ready[:subject])
      assert_match "https://outlook.example/draft-1", ready[:html]
      assert_match(/FAILED/, failure[:subject])
      assert_match "SharePoint down", failure[:html]
    end

    test "operator alert subjects reflect run_date, not wall-clock today" do
      notifier, graph = build

      travel_to Date.new(2026, 7, 11) do
        notifier.failure(recipients: [ "ops@bedlamfringe.co.uk" ], error_text: "boom",
                         run_date: "9 July 2026")
      end

      assert_includes graph.send_mails.sole[:subject], "9 July 2026"
      assert_not_includes graph.send_mails.sole[:subject], "2026-07-11"
    end

    test "the rendered email is a complete HTML document, not a bare fragment" do
      notifier, graph = build

      notifier.rejection(to: "pat@example.com", payee_name: "Pat Producer", auto_number: 7,
                         amount: 12.5, budget_name: "Props", description: "Fake blood",
                         reason: "Missing VAT breakdown.")

      html = graph.send_mails.sole[:html]
      assert_match(/\A<!DOCTYPE html>/, html)
      assert_includes html, "<html"
      assert_includes html, '<meta charset="utf-8">'
      assert_includes html, "<title>Your Bedlam expense #7 was not approved</title>"
    end

    test "a Graph send failure propagates so callers can rescue it" do
      notifier, graph = build
      graph.fail_send = true

      assert_raises(Reimbursements::GraphAuth::Error) do
        notifier.failure(recipients: [ "ops@bedlamfringe.co.uk" ], error_text: "boom", run_date: "9 July 2026")
      end
    end
  end
end
