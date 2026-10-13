require "application_system_test_case"

class Admin::UserMergeTest < ApplicationSystemTestCase
  test "choosing a user to merge opens the preview at a URL naming that user" do
    target = users(:admin)
    source = FactoryBot.create(:member, first_name: "Petronella", last_name: "Mergeworthy")
    login_as target

    visit merge_admin_user_path(target)
    tom_select_click "Petronella Mergeworthy", select_id: "source_user_id", search: "Petro"
    click_on "Preview Merge"

    assert_text "Merge Preview"
    assert_current_path merge_admin_user_path(target, source_user_id: source.id)
  end
end
