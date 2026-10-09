require "test_helper"

module Reimbursements
  class NotifierTest < ActiveSupport::TestCase
    include ReimbursementsTestHelpers

    MAILBOX = "send@bedlamfringe.co.uk".freeze
    FINANCE = "finance@bedlamfringe.co.uk".freeze

    def cost_centre(name: "Bedlam Fringe 2026", notification_email: FINANCE)
      CostCentre.new(key: "fringe", name: name, eusa_code: "F40", notification_email: notification_email,
                     receive_mailbox: MAILBOX, send_mailbox: MAILBOX)
    end

    def build(centre: cost_centre, **opts)
      graph = FakeGraphClient.new
      [ Notifier.new(cost_centre: centre, graph: graph, **opts), graph ]
    end

    test "rejection sends from the mailbox with the payee, subject and rendered body" do
      notifier, graph = build

      notifier.rejection(to: "pat@example.com", greeting_name: "Pat", auto_number: 7, record_id: 42,
                         amount: 12.5, budget_name: "Props", description: "Fake blood",
                         reason: "Receipt is missing the VAT breakdown.")

      mail = graph.send_mails.sole
      assert_equal MAILBOX, mail[:mailbox]
      assert_equal [ "pat@example.com" ], mail[:to]
      assert_match(/expense #7/i, mail[:subject])
      assert_match "Hi Pat,", mail[:html]
      assert_match "Receipt is missing the VAT breakdown.", mail[:html]
      assert_match "12.50", mail[:html]
      assert_match "Props", mail[:html]
      assert_match(/\A<!DOCTYPE html>/, mail[:html], "a complete document, not a bare fragment")
      assert_includes mail[:html], "<html"
      assert_includes mail[:html], '<meta charset="utf-8">'
      assert_includes mail[:html], "<title>Your Bedlam Fringe 2026 expense #7 was not approved</title>"
    end

    test "producer_notification lists the payee's expenses and totals" do
      notifier, graph = build
      line_items = [ { auto_number: 7, record_id: 42, amount: "12.50", budget_name: "Props",
                       description: "Fake blood" },
                     { auto_number: 8, record_id: 43, amount: "8.00", budget_name: "Props",
                       description: "Brushes" } ]

      notifier.producer_notification(to: "alice@example.com", greeting_name: "Alice",
                                     line_items: line_items, bacs_date: Date.new(2026, 5, 13), total: "20.50")

      mail = graph.send_mails.sole
      assert_equal "[Bedlam Fringe 2026] 2 expenses submitted for payment", mail[:subject]
      assert_match "Hi Alice,", mail[:html]
      assert_match "Fake blood", mail[:html]
      assert_match "20.50", mail[:html]
      assert_match "2026-05-13", mail[:html]
    end

    test "operator alerts render their bodies and carry the standard subjects" do
      notifier, graph = build
      recipients = [ "ops@bedlamfringe.co.uk" ]

      notifier.pending_reminder(recipients: recipients, run_date: "9 July 2026", threshold_days: 3,
                                rows: [ { auto_number: 7, record_id: 42, payee_name: "Pat", amount: "12.50",
                                          age_days: 5 } ])
      notifier.approved_ready(recipients: recipients, total: "40.00", run_date: "9 July 2026",
                              next_run_day: "Tuesday 14 July",
                              expenses: [ { auto_number: 3, payee_name: "Sam", amount: "40.00",
                                            budget_name: "Props", description: "Paint",
                                            flags: [ "no receipt" ] } ])
      notifier.batch_ready(recipients: recipients, total: "52.50", run_date: "9 July 2026",
                           draft_link: "https://outlook.example/draft-1",
                           expenses: [ { auto_number: 3, payee_name: "Sam", amount: "40.00",
                                         budget_name: "Props", description: "Paint" } ])
      notifier.failure(recipients: recipients, error_text: "SharePoint down", run_date: "9 July 2026")

      reminder, approved, ready, failure = graph.send_mails
      assert_equal recipients, reminder[:to]
      assert_match(/awaiting approval/, reminder[:subject])
      assert_match "5 day", reminder[:html]
      # The ready-to-batch alert carries NO draft link; a flagged claim is listed with its reason
      # and counted in the subject, not diverted into a separate email.
      assert_match(/ready to batch/, approved[:subject])
      assert_match(/1 flagged/, approved[:subject])
      assert_match "no receipt", approved[:html]
      assert_match "Tuesday 14 July", approved[:html]
      assert_match "Build Batch", approved[:html]
      assert_no_match(/outlook\.example/, approved[:html])
      assert_match(/Draft ready/, ready[:subject])
      assert_match "https://outlook.example/draft-1", ready[:html]
      assert_match(/FAILED/, failure[:subject])
      assert_match "SharePoint down", failure[:html]
    end

    # The interactive build runs no readiness checks, so the email must not claim any.
    test "batch_ready states the batch it built, with a count that reads right for one or several" do
      notifier, graph = build
      row = { auto_number: 3, payee_name: "Sam", amount: "40.00", budget_name: "Props",
              description: "Paint" }

      [ [ row ], [ row, row, row ] ].each do |expenses|
        notifier.batch_ready(recipients: [ "ops@example.com" ], expenses: expenses, total: "40.00",
                             draft_link: nil, run_date: "9 July 2026")
      end

      one, three = graph.send_mails.map { |mail| Nokogiri::HTML(mail[:html]).text.squish }
      assert_includes one, "You built a BACS batch of 1 approved expense on 9 July 2026."
      assert_includes three, "You built a BACS batch of 3 approved expenses on 9 July 2026."
      [ one, three ].each { |text| assert_no_match(/readiness|checks/, text) }
    end

    test "owner_sign_off_reminder greets the owner and lists their claims" do
      notifier, graph = build

      notifier.owner_sign_off_reminder(
        to: [ "olive@example.com" ], greeting_name: "Olive", run_date: "9 July 2026",
        rows: [ { auto_number: 7, payee_name: "Pat", amount: "12.50", budget_name: "Owned Set",
                  description: "Timber", age_days: 5 } ]
      )

      mail = graph.send_mails.sole
      assert_equal MAILBOX, mail[:mailbox]
      assert_equal [ "olive@example.com" ], mail[:to]
      assert_match(/1 claim needs your sign-off \(9 July 2026\)/, mail[:subject])
      assert_match "Hi Olive,", mail[:html]
      assert_match "Owned Set", mail[:html]
      assert_match "Timber", mail[:html]
      assert_match "12.50", mail[:html]
      assert_match "5 day", mail[:html]
      assert_match "My Budgets", mail[:html]
    end

    test "owner_sign_off_reminder pluralises its subject for several claims" do
      notifier, graph = build
      row = { auto_number: 7, payee_name: "Pat", amount: "12.50", budget_name: "Set",
              description: "Timber", age_days: 5 }

      notifier.owner_sign_off_reminder(to: [ "olive@example.com" ], greeting_name: "Olive",
                                       rows: [ row, row.merge(auto_number: 8) ],
                                       run_date: "9 July 2026")

      assert_match(/2 claims need your sign-off/, graph.send_mails.sole[:subject])
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

    # No subject or sign-off may hardcode "Bedlam Fringe": a termtime claimant must never be
    # emailed about a Fringe expense. Copy comes from the cost centre threaded into Notifier.
    test "every subject and sign-off comes from the cost centre, never a literal Bedlam" do
      centre = cost_centre(name: "Termtime Payments")
      notifier, graph = build(centre: centre)
      recipients = [ "ops@example.com" ]
      row = { auto_number: 7, record_id: 42, payee_name: "Pat", amount: "12.50", age_days: 5,
              budget_name: "Props", description: "Paint", flags: [] }

      notifier.rejection(to: "pat@example.com", greeting_name: "Pat", auto_number: 7, record_id: 42, amount: 12.5,
                         budget_name: "Props", description: "Paint", reason: "No receipt.")
      notifier.producer_notification(to: "pat@example.com", greeting_name: "Pat", total: "12.50",
                                     line_items: [ row ], bacs_date: Date.new(2026, 5, 13))
      notifier.pending_reminder(recipients: recipients, rows: [ row ], run_date: "9 July 2026",
                                threshold_days: 3)
      notifier.owner_sign_off_reminder(to: [ "olive@example.com" ], greeting_name: "Olive",
                                       rows: [ row ], run_date: "9 July 2026")
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

    PORTAL = "https://www.example.com/admin/reimbursements".freeze

    def owner_row(**attrs)
      { auto_number: 7, payee_name: "Pat", amount: "12.50", budget_id: 1, budget_name: "Set",
        description: "Timber", age_days: 5 }.merge(attrs)
    end

    def remind_owner(*rows)
      notifier, graph = build
      notifier.owner_sign_off_reminder(to: [ "olive@example.com" ], greeting_name: "Olive",
                                       rows: rows, run_date: "9 July 2026")
      graph.send_mails.sole[:html]
    end

    test "owner reminder counts the budgets, not the claims, and links to My Budgets" do
      html = remind_owner(owner_row, owner_row(auto_number: 8))

      assert_includes html, "charged to a budget you own"
      assert_includes html, %(href="#{PORTAL}/my_budgets")
      assert_includes remind_owner(owner_row, owner_row(budget_id: 2)), "charged to budgets you own",
                      "two lines can share a display name"
    end

    test "owner reminder names a budget's other owners on that budget only" do
      html = remind_owner(owner_row(also_owned_by: "Ann Other"), owner_row(budget_id: 2, budget_name: "Props"))

      assert_includes html, "Set (also owned by Ann Other)"
      assert_equal 1, html.scan("also owned by").size
    end

    test "rejection links to the claim, a new claim and the cost centre's contact address" do
      notifier, graph = build
      notifier.rejection(to: "pat@example.com", greeting_name: "Pat", auto_number: 7, record_id: 42,
                         amount: 12.5, budget_name: "Props", description: "Paint", reason: "No receipt.")

      html = graph.send_mails.sole[:html]
      assert_includes html, %(href="#{PORTAL}/expenses/42")
      assert_includes html, %(href="#{PORTAL}/expenses/new")
      assert_includes html, %(href="mailto:#{FINANCE}")
      assert_not_includes html, "feel free"
    end

    test "producer notification numbers and links each claim and names the contact address" do
      notifier, graph = build
      notifier.producer_notification(to: "pat@example.com", greeting_name: "Pat", total: "12.50",
                                     bacs_date: Date.new(2026, 5, 13),
                                     line_items: [ { auto_number: 7, record_id: 42, amount: "12.50",
                                                     budget_name: "Props", description: "Paint" } ])

      html = graph.send_mails.sole[:html]
      assert_includes html, %(href="#{PORTAL}/expenses/42">#7</a>)
      assert_includes html, %(contact us at <a href="mailto:#{FINANCE}")
      assert_not_includes html, "let me know"
    end

    test "operator emails link to the portal pages they talk about" do
      notifier, graph = build
      recipients = [ "ops@bedlamfringe.co.uk" ]
      row = { auto_number: 7, record_id: 42, payee_name: "Pat", amount: "12.50", age_days: 5,
              budget_name: "Props", description: "Paint", flags: [] }

      notifier.pending_reminder(recipients: recipients, rows: [ row ], run_date: "9 July 2026",
                                threshold_days: 3)
      notifier.approved_ready(recipients: recipients, expenses: [ row ], total: "12.50",
                              run_date: "9 July 2026")
      notifier.batch_ready(recipients: recipients, expenses: [ row ], total: "12.50", batch_id: 9,
                           draft_link: nil, run_date: "9 July 2026")
      notifier.batch_ready(recipients: recipients, expenses: [ row ], total: "12.50",
                           draft_link: nil, run_date: "9 July 2026")
      notifier.failure(recipients: recipients, error_text: "boom", run_date: "9 July 2026")

      pending, approved, ready, ready_without_id, failure = graph.send_mails.map { |mail| mail[:html] }
      assert_includes pending, %(href="#{PORTAL}/review?cost_centre=fringe&amp;tab=to_approve")
      assert_includes pending, %(href="#{PORTAL}/expense_edits/42/edit">#7</a>)
      assert_includes approved, %(href="#{PORTAL}/review?cost_centre=fringe&amp;tab=approved")
      assert_includes approved, %(href="#{PORTAL}/batches/new?cost_centre=fringe")
      assert_includes ready, %(href="#{PORTAL}/batches/9")
      assert_includes ready_without_id, %(href="#{PORTAL}/batches")
      assert_includes failure, %(href="#{PORTAL}/batches/new?cost_centre=fringe")
      assert_includes failure, "forward this email to IT"
      assert_not_includes failure, "server logs"
    end

    test "producer emails never offer the polled receive mailbox as a contact" do
      notifier, graph = build(centre: cost_centre(notification_email: nil))
      notifier.rejection(to: "pat@example.com", greeting_name: "Pat", auto_number: 7, record_id: 42,
                         amount: 12.5, budget_name: "Props", description: "Paint", reason: "No receipt.")
      notifier.producer_notification(to: "pat@example.com", greeting_name: "Pat", total: "12.50",
                                     bacs_date: Date.new(2026, 5, 13),
                                     line_items: [ { auto_number: 7, record_id: 42, amount: "12.50",
                                                     budget_name: "Props", description: "Paint" } ])

      graph.send_mails.each do |mail|
        assert_not_includes mail[:html], "mailto:#{MAILBOX}"
        assert_not_includes mail[:html], "contact us"
      end
    end

    test "a missing mailer host fails loudly rather than linking to http:///" do
      config = Rails.application.config.action_mailer
      original = config.default_url_options
      config.default_url_options = { protocol: "https" }
      notifier, = build

      assert_raises(KeyError) do
        notifier.failure(recipients: [ "ops@bedlamfringe.co.uk" ], error_text: "boom", run_date: "9 July 2026")
      end
    ensure
      config.default_url_options = original
    end

    test "no template tells a lone owner that one of several can sign off" do
      Rails.root.glob("app/views/reimbursements/emails/*.erb").each do |template|
        assert_not_includes template.read, "one of you", "#{template} assumes several owners"
      end
    end

    test "a Graph send failure propagates so callers can rescue it" do
      notifier, graph = build
      graph.fail_send = true

      assert_raises(::GraphAuth::Error) do
        notifier.failure(recipients: [ "ops@bedlamfringe.co.uk" ], error_text: "boom", run_date: "9 July 2026")
      end
    end
  end
end
