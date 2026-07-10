require "test_helper"

module Reimbursements
  class BatchMailerTest < ActionMailer::TestCase
    def line_items
      [ { amount: "12.50", budget_name: "Props", description: "Fake blood" },
        { amount: "8.00", budget_name: "Props", description: "Brushes" } ]
    end

    test "producer_notification lists the payee's expenses and total" do
      email = BatchMailer.producer_notification(
        recipient_email: "alice@example.com", recipient_name: "Alice Producer",
        line_items: line_items, bacs_date: Date.new(2026, 5, 13), total: "20.50"
      )

      assert_equal [ "alice@example.com" ], email.to
      assert_equal "[Bedlam Fringe] 2 expenses submitted for payment", email.subject
      body = email.body.to_s
      assert_includes body, "Hi Alice Producer,"
      assert_includes body, "Fake blood"
      assert_includes body, "12.50"
      assert_includes body, "20.50"
      assert_includes body, "2026-05-13"
    end

    test "singularises the subject for a single expense" do
      email = BatchMailer.producer_notification(
        recipient_email: "bob@example.com", recipient_name: "Bob",
        line_items: [ line_items.first ], bacs_date: Date.new(2026, 5, 13), total: "12.50"
      )
      assert_equal "[Bedlam Fringe] 1 expense submitted for payment", email.subject
    end

    test "delivers later so a slow SMTP hop can't stall batch processing" do
      assert_enqueued_emails 1 do
        BatchMailer.producer_notification(
          recipient_email: "alice@example.com", recipient_name: "Alice",
          line_items: line_items, bacs_date: Date.new(2026, 5, 13), total: "20.50"
        ).deliver_later
      end
    end
  end
end
