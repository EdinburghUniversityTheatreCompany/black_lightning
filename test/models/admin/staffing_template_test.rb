# == Schema Information
#
# Table name: admin_staffing_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class StaffingTemplateTest < ActionView::TestCase
  test "as_json" do
    @staffing_template = FactoryBot.create(:staffing_template, job_count: 5)

    json = @staffing_template.as_json

    assert json.is_a? Hash
    assert json.key? "staffing_jobs"
  end
end
