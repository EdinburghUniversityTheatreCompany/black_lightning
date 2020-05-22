require 'test_helper'

class Admin::FaultReportTest < ActionView::TestCase
  test 'should return the correct css class' do
    @fault_report = FactoryBot.create(:fault_report)

    helper_compare_css_class 'warning', 'in_progress'
    helper_compare_css_class 'warning', :on_hold

    helper_compare_css_class 'error', 'cant_fix'
    helper_compare_css_class 'error', :wont_fix

    helper_compare_css_class 'success', 'completed'

    helper_compare_css_class '', :reported
  end

  def helper_compare_css_class(expected_class, state)
    @fault_report.status = state
    assert_equal expected_class, @fault_report.css_class
  end
end
