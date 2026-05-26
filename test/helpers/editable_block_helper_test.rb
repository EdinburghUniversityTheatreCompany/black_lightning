require "test_helper"

class EditableBlockHelperTest < ActionView::TestCase
  def current_ability
    users(:admin).ability
  end

  test "should display editable block" do
    editable_block = FactoryBot.create :editable_block

    assert_raises ActionView::Template::Error do
      display_block(editable_block.name, false)
    end
  end

  test "displaying block on admin page should set to admin page to true" do
    editable_block = FactoryBot.create(:editable_block, admin_page: false)

    assert_raises ActionView::Template::Error do
      display_block(editable_block.name, true)
    end

    assert editable_block.reload.admin_page
  end

  test "displays a warning when the editable block does not exist" do
    result = display_block("pineapple", false)
    assert_includes result, "Block not defined."
    assert_includes result, btn_classes(:primary)
    assert_includes result, "editable_blocks/new?name=pineapple"
  end

  test "existing block should exist" do
    editable_block = FactoryBot.create :editable_block
    assert block_exists?(editable_block.name)
  end

  test "non-existing block should not exist" do
    assert_not block_exists?("hexagon")
  end
end
