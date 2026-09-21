require "application_system_test_case"

# The preview is a POST that renders a page rather than redirecting. A request-level test cannot
# see what the browser does with that response; only clicking the real button can.
class Admin::MembershipImportsTest < ApplicationSystemTestCase
  SHEET = "Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email\n" \
          "s9999999\tNew Person\t07/09/2025\tStudent\tnew.person@example.com"

  setup do
    login_as users(:admin)
  end

  test "pasting a sheet and clicking Preview Import shows the review page" do
    visit new_admin_membership_import_url

    # Set outright: Capybara TYPES the first characters of a long value, and a typed Tab leaves the field.
    page.execute_script("document.querySelector('textarea[name=paste_data]').value = arguments[0]", SHEET)
    click_on "Preview Import", match: :first

    assert_review_page
  end

  test "uploading an xlsx and clicking Preview Import shows the review page" do
    visit new_admin_membership_import_url

    attach_file "xlsx_file", sheet_as_xlsx
    all(:button, "Preview Import").last.click

    assert_review_page
  end

  test "an empty paste comes back to the form with its error on screen" do
    visit new_admin_membership_import_url

    click_on "Preview Import", match: :first

    assert_selector ".swal2-container", text: "Please provide data to import", wait: 5
    assert_current_path new_admin_membership_import_path
  end

  private

  def assert_review_page
    assert_text "Found 1 row(s) to process."
    assert_text "New Person"
    assert_current_path preview_admin_membership_imports_path
  end

  def sheet_as_xlsx
    require "caxlsx"
    path = Rails.root.join("tmp", "membership_import_#{Process.pid}.xlsx")
    package = Axlsx::Package.new
    package.workbook.add_worksheet { |sheet| SHEET.lines(chomp: true).each { |line| sheet.add_row(line.split("\t"), types: :string) } }
    package.serialize(path.to_s)
    path
  end
end
