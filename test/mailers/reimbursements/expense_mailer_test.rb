require "test_helper"

module Reimbursements
  class ExpenseMailerTest < ActionMailer::TestCase
    test "rejection_email addresses the payee and renders the claim details" do
      mail = ExpenseMailer.rejection_email(
        email: "pat@example.com", payee_name: "Pat Producer", auto_number: 7,
        amount: 12.5, budget_name: "Props", description: "Fake blood",
        reason: "Receipt is missing the VAT breakdown."
      )

      assert_equal [ "pat@example.com" ], mail.to
      assert_match(/expense #7/i, mail.subject)

      body = mail.html_part.body.to_s
      assert_match "Pat Producer", body
      assert_match "Receipt is missing the VAT breakdown.", body
      assert_match "12.50", body
      assert_match "Props", body
      assert_match "Fake blood", body

      text = mail.text_part.body.to_s
      assert_match "Pat Producer", text
      assert_match "12.50", text
    end
  end
end
