require "application_system_test_case"

##
# System test for the Stimulus-driven template_loader_controller.
#
# Verifies that:
#   (a) the template dropdown is populated from the JSON endpoint on page load;
#   (b) selecting a template shows a summary of its items;
#   (c) clicking "Load Template" inserts Cocoon rows and populates them with the
#       template's field values.
##
class Admin::QuestionTemplatesTest < ApplicationSystemTestCase
  setup do
    login_as users(:admin)
  end

  # ── Proposals call form (items_type = questions) ─────────────────────────────
  # The call form has no preconditions (no future-event requirement), making it
  # the most reliable test surface for the "questions" items_type path.

  test "proposals call form: dropdown is populated from the JSON endpoint" do
    visit new_admin_proposals_call_path

    # Open the Load Template modal
    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      # Wait for AJAX to populate the dropdown.
      # Fixtures have two templates: mainterm and lunchtime
      assert_selector "select option[value]", wait: 5
      assert_selector "select option", text: "Question Call Template (Mainterm)", wait: 3
    end
  end

  test "proposals call form: selecting a template shows a summary" do
    visit new_admin_proposals_call_path

    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      assert_selector "select option", text: "Question Call Template (Mainterm)", wait: 5
      select "Question Call Template (Mainterm)" # , from: "template_list"

      # Summary should appear with the questions from the mainterm fixture
      assert_selector "#template_summary ul#template_items_list", wait: 3
      assert_text "Vikings"
      assert_text "Pineapples"
    end
  end

  test "proposals call form: Load Template button is disabled until a template is selected" do
    visit new_admin_proposals_call_path

    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      # Initially disabled
      assert_selector "#template_load[disabled]"

      # Select a template — button should become enabled
      assert_selector "select option", text: "Question Call Template (Mainterm)", wait: 5
      select "Question Call Template (Mainterm)", from: "template_list"

      assert_no_selector "#template_load.disabled", wait: 3
    end
  end

  test "proposals call form: Load Template inserts questions with populated fields" do
    visit new_admin_proposals_call_path

    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      assert_selector "select option", text: "Question Call Template (Mainterm)", wait: 5
      select "Question Call Template (Mainterm)", from: "template_list"
      assert_no_selector "#template_load.disabled", wait: 3
      # Click the Load Template button inside the modal footer
      find("#template_load").click
    end

    # Modal closes (data-dismiss). Cocoon should have inserted question rows
    # with the template's question text values. Wait for BOTH questions.
    # The mainterm template fixture has 2 questions (Vikings, Pineapples).
    assert_selector "#questions .nested-fields.question", count: 2, wait: 8
    question_texts = all("#questions [name$='[question_text]']", visible: :all).map(&:value)
    assert_includes question_texts, "Vikings"
    assert_includes question_texts, "Pineapples"
  end

  # ── Staffing new form (items_type = jobs) ────────────────────────────────────
  # Uses FactoryBot to create a template with jobs (no fixtures exist for
  # staffing templates with jobs).

  test "staffing new form: dropdown is populated from the JSON endpoint" do
    template = FactoryBot.create(:staffing_template, job_count: 2)

    visit new_admin_staffing_path

    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      assert_selector "select option[value]", wait: 5
      assert_selector "select option", text: template.name, wait: 3
    end
  end

  test "staffing new form: Load Template inserts jobs with populated names" do
    template = FactoryBot.create(:staffing_template, job_count: 0)
    job1 = FactoryBot.create(:unstaffed_staffing_job, staffable: template, name: "Stage Manager")
    job2 = FactoryBot.create(:unstaffed_staffing_job, staffable: template, name: "Sound Operator")

    visit new_admin_staffing_path

    find("button[data-action=\"click->template-loader#open\"]").click

    within "#template_modal" do
      assert_selector "select option", text: template.name, wait: 5
      select template.name, from: "template_list"
      assert_no_selector "#template_load.disabled", wait: 3
      find("#template_load").click
    end

    # Cocoon should have inserted job rows with the template's job names.
    assert_selector ".nested-fields [name$='[name]']", count: 2, wait: 8
    job_names = all(".nested-fields [name$='[name]']").map(&:value)
    assert_includes job_names, "Stage Manager"
    assert_includes job_names, "Sound Operator"
  end
end
