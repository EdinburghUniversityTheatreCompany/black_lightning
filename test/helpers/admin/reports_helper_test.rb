require "test_helper"

class Admin::ReportsHelperTest < ActionView::TestCase
  include LinkHelper

  test "should get reports list" do
    assert_equal(
      {
        roles: "Roles",
        members: "Members",
        newsletter_subscribers: "Newsletter Subscribers",
        staffing: "Staffing"
      },
      list_reports
    )
  end

  test "should get report link" do
    link = get_report_link(:roles, "Roles")
    assert_includes link, 'action="/admin/reports/roles"'
    assert_includes link, 'value="put"'
    assert_includes link, ">Roles<"
  end
end
