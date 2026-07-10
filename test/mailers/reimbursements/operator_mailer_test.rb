require "test_helper"

module Reimbursements
  class OperatorMailerTest < ActionMailer::TestCase
    RECIPIENTS = [ "ops@bedlamfringe.co.uk" ].freeze

    test "pending_reminder lists the stuck submissions" do
      mail = OperatorMailer.pending_reminder(
        recipients: RECIPIENTS, threshold_days: 3, run_date: "9 July 2026",
        rows: [ { auto_number: 7, payee_name: "Pat Producer", amount: "12.50", age_days: 5 } ]
      )

      assert_equal RECIPIENTS, mail.to
      assert_match(/awaiting approval/, mail.subject)
      [ mail.html_part, mail.text_part ].each do |part|
        body = part.body.to_s
        assert_match "Pat Producer", body
        assert_match "12.50", body
        assert_match "5 day", body
      end
    end

    test "manual_review lists issues and the next run day" do
      mail = OperatorMailer.manual_review(
        recipients: RECIPIENTS, unblocked_count: 2, run_date: "9 July 2026", next_run_day: "Tuesday 14 July",
        issues: [ { auto_number: 3, payee_name: "Sam", amount: "40.00", reason: "AI review: amount mismatch" } ]
      )

      assert_match(/Manual review needed/, mail.subject)
      body = mail.html_part.body.to_s
      assert_match "amount mismatch", body
      assert_match "Tuesday 14 July", body
      assert_match "2 other", body
    end

    test "batch_ready carries the draft link and totals" do
      mail = OperatorMailer.batch_ready(
        recipients: RECIPIENTS, total: "52.50", draft_link: "https://outlook.example/draft-1",
        run_date: "9 July 2026",
        expenses: [ { auto_number: 3, payee_name: "Sam", amount: "40.00", budget_name: "Props", description: "Paint" } ]
      )

      assert_match(/Draft ready/, mail.subject)
      body = mail.html_part.body.to_s
      assert_match "https://outlook.example/draft-1", body
      assert_match "52.50", body
      assert_match "Props", body
    end

    test "failure surfaces the error text" do
      mail = OperatorMailer.failure(recipients: RECIPIENTS, error_text: "SharePoint down", run_date: "9 July 2026")

      assert_match(/FAILED/, mail.subject)
      assert_match "SharePoint down", mail.html_part.body.to_s
      assert_match "SharePoint down", mail.text_part.body.to_s
    end
  end
end
