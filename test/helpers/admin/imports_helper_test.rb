require "test_helper"

class Admin::ImportsHelperTest < ActionView::TestCase
  test "import_choice renders a radio and its label under one id, unchecked by default" do
    html = import_choice(3, "merge_7", "Merge with Finbar", checked: true)

    assert_select Nokogiri::HTML.fragment(html), "div.form-check" do
      assert_select "input[type=radio][name='actions[3]'][value=merge_7][id=action_3_merge_7][checked]"
      assert_select "label[for=action_3_merge_7]", text: "Merge with Finbar"
    end
    assert_select Nokogiri::HTML.fragment(import_choice(0, "skip", "Skip")), "input[id=action_0_skip]:not([checked])"
  end

  test "import_match_label names the id or email that matched" do
    row = { user_id: 12, student_id: "s1234567", associate_id: "ASSOC1", email: "a@example.com" }

    assert_equal "User ID 12", import_match_label(match_type: :user_id, row: row)
    assert_equal "s1234567", import_match_label(match_type: :student_id, row: row)
    assert_equal "ASSOC1", import_match_label(match_type: :associate_id, row: row)
    assert_equal "a@example.com", import_match_label(match_type: nil, row: row)
  end
end
