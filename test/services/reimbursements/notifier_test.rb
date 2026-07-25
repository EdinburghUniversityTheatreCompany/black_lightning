require "test_helper"

module Reimbursements
  class NotifierTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    Person = Struct.new(:name, :email, keyword_init: true)
    PaidExpense = Struct.new(:description, :amount, :auto_number, keyword_init: true)

    MAILBOX = "send@bedlamfringe.co.uk".freeze

    def cost_centre(name: "Bedlam Fringe 2026")
      CostCentre.new(key: "fringe", name: name, eusa_code: "F40",
                     receive_mailbox: MAILBOX, send_mailbox: MAILBOX)
    end

    def build(centre: cost_centre, **opts)
      graph = FakeGraphClient.new
      [ Notifier.new(cost_centre: centre, graph: graph, **opts), graph ]
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
      assert_match "The Bedlam Fringe 2026 finance team", mail[:html],
                   "the sign-off must be the cost centre's name, not a hardcoded one"
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
      assert_equal "[Bedlam Fringe 2026] 2 expenses submitted for payment", mail[:subject]
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
      assert_includes html, "<title>Your Bedlam Fringe 2026 expense #7 was not approved</title>"
    end

    # The portal is multi-cost-centre (termtime becomes a second row), so no
    # subject or sign-off may hardcode "Bedlam Fringe" — a termtime claimant
    # must never be emailed about a Fringe expense. Everything is driven off
    # the cost centre threaded into Notifier, so a second centre gets correct
    # copy the moment its row exists. payment_confirmation is covered by its own
    # sign-off assertion below rather than this sweep: its body still carries one
    # literal "Bedlam Fringe" in a thank-you line Mick is removing separately.
    test "every subject and sign-off comes from the cost centre, never a literal Bedlam" do
      centre = cost_centre(name: "Termtime Payments")
      notifier, graph = build(centre: centre)
      recipients = [ "ops@example.com" ]
      row = { auto_number: 7, payee_name: "Pat", amount: "12.50", age_days: 5,
              budget_name: "Props", description: "Paint", reason: "AI review: amount mismatch" }

      notifier.rejection(to: "pat@example.com", payee_name: "Pat", auto_number: 7, amount: 12.5,
                         budget_name: "Props", description: "Paint", reason: "No receipt.")
      notifier.producer_notification(to: "pat@example.com", recipient_name: "Pat", total: "12.50",
                                     line_items: [ row ], bacs_date: Date.new(2026, 5, 13))
      notifier.pending_reminder(recipients: recipients, rows: [ row ], run_date: "9 July 2026",
                                threshold_days: 3)
      notifier.manual_review(recipients: recipients, issues: [ row ], unblocked_count: 2,
                             run_date: "9 July 2026", next_run_day: "Tuesday 14 July")
      notifier.approved_ready(recipients: recipients, expenses: [ row ], total: "40.00",
                              run_date: "9 July 2026")
      notifier.batch_ready(recipients: recipients, expenses: [ row ], total: "52.50",
                           draft_link: "https://outlook.example/draft-1", run_date: "9 July 2026")
      notifier.failure(recipients: recipients, error_text: "boom", run_date: "9 July 2026")

      graph.send_mails.each do |mail|
        assert_not_includes mail[:subject], "Bedlam",
                            "#{mail[:subject].inspect} hardcodes the Fringe cost centre"
        assert_not_includes mail[:html], "Bedlam",
                            "the body of #{mail[:subject].inspect} hardcodes the Fringe cost centre"
      end
      operator_subjects = graph.send_mails.map { |mail| mail[:subject] }.last(5)
      assert(operator_subjects.all? { |subject| subject.start_with?("[Termtime Payments]") },
             "operator subjects must share one cost-centre-derived prefix: #{operator_subjects.inspect}")
      assert_includes graph.send_mails.last[:html], "Termtime Payments BACS (automated)"
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
