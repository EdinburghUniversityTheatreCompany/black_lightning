require "application_system_test_case"

class Admin::MassMailsTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
    @mass_mail = MassMail.create!(subject: "Fringe auditions", body: "Auditions open on Monday.",
                                  draft: true, send_date: 1.day.from_now)
  end

  test "Send asks first, and Cancel leaves the mail a draft" do
    visit edit_admin_mass_mail_path(@mass_mail)
    click_button "Send"

    assert_selector ".swal2-popup", text: "Once you confirm, it can no longer be edited or deleted."
    click_button "Cancel"

    assert_no_selector ".swal2-popup"
    assert_predicate @mass_mail.reload, :draft?
  end

  test "confirming Send sends the mail" do
    visit edit_admin_mass_mail_path(@mass_mail)
    click_button "Send"
    within(".swal2-popup") { click_button "Yes" }

    assert_text "Mass mail will be sent."
    assert_not_predicate @mass_mail.reload, :draft?
  end
end
