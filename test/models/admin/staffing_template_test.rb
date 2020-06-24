require 'test_helper'

class StaffingTemplateTest < ActionView::TestCase
  test 'as_json' do
    @staffing_template = FactoryBot.create(:staffing_template, job_count: 5)

    json = @staffing_template.as_json

    assert json.is_a? Hash
    assert json.key? 'staffing_jobs'
  end
end
