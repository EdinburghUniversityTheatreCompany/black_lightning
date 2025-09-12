# == Schema Information
#
# Table name: fault_reports
#
# *id*::             <tt>integer, not null, primary key</tt>
# *item*::           <tt>string(255)</tt>
# *description*::    <tt>text(65535)</tt>
# *severity*::       <tt>integer, default("annoying")</tt>
# *status*::         <tt>integer, default("reported")</tt>
# *reported_by_id*:: <tt>integer</tt>
# *fixed_by_id*::    <tt>integer</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::FaultReportTest < ActionView::TestCase
  test "should return the correct css class" do
    @fault_report = FactoryBot.create(:fault_report)

    helper_compare_css_class "table-warning", "in_progress"
    helper_compare_css_class "table-warning", :on_hold

    helper_compare_css_class "table-danger", "cant_fix"
    helper_compare_css_class "table-danger", :wont_fix

    helper_compare_css_class "table-success", "completed"

    helper_compare_css_class "", :reported
  end

  def helper_compare_css_class(expected_class, state)
    @fault_report.status = state
    assert_equal expected_class, @fault_report.css_class
  end
end
