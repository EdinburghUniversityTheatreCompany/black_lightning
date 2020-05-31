require 'test_helper'

class Admin::ReportsHelperTest < ActionView::TestCase
  test 'should get reports list' do
    assert_equal(
      {
        roles: 'Roles',
        members: 'Members',
        newsletter_subscribers: 'Newsletter Subscribers',
        staffing: 'Staffing'
      },
      list_reports
    )
  end

  test 'should get report link' do
    assert_equal '<a rel="nofollow" data-method="put" href="/admin/reports/roles">Roles</a>', get_report_link(:roles, 'Roles')
  end
end
