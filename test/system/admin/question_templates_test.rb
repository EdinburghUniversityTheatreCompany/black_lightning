require "application_system_test_case"

# Drives template_loader_controller on the call form (questions) and the staffing form (jobs).
class Admin::QuestionTemplatesTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  test "proposals call form: loading a template inserts its questions" do
    visit new_admin_proposals_call_path

    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      assert_selector "#template_load[disabled]"

      assert_selector "select option", text: "Question Call Template (Mainterm)", wait: 5
      select "Question Call Template (Mainterm)", from: "template_list"

      assert_selector "#template_summary ul#template_items_list", wait: 3
      assert_text "Vikings"
      assert_text "Pineapples"
      assert_no_selector "#template_load[disabled]", wait: 3
      find("#template_load").click
    end

    assert_selector "#questions .nested-fields.question", count: 2, wait: 8
    question_texts = all("#questions [name$='[question_text]']", visible: :all).map(&:value)
    assert_includes question_texts, "Vikings"
    assert_includes question_texts, "Pineapples"
  end

  test "staffing new form: Load Template inserts jobs with populated names" do
    template = FactoryBot.create(:staffing_template, job_count: 0)
    FactoryBot.create(:unstaffed_staffing_job, staffable: template, name: "Stage Manager")
    FactoryBot.create(:unstaffed_staffing_job, staffable: template, name: "Sound Operator")

    visit new_admin_staffing_path

    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      assert_selector "select option", text: template.name, wait: 5
      select template.name, from: "template_list"
      assert_no_selector "#template_load[disabled]", wait: 3
      find("#template_load").click
    end

    assert_selector ".nested-fields [name$='[name]']", count: 2, wait: 8
    job_names = all(".nested-fields [name$='[name]']").map(&:value)
    assert_includes job_names, "Stage Manager"
    assert_includes job_names, "Sound Operator"
  end
end
