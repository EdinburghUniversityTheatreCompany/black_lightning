require 'test_helper'

class EditableBlockHelperTest < ActionView::TestCase
  test 'should display editable block' do
    skip 'This test does not work because the helper relies on the presence of current_ability'

    editable_block = FactoryBot.create :editable_block

    display_block editable_block.name, false

    assert_response :success
  end

  test 'displaying block on admin page should set to admin page to true' do
    skip 'This test does not work because the helper relies on the presence of current_ability'

    editable_block = FactoryBot.create :editable_block, admin_page: false

    display_block editable_block.name, true

    assert editable_block.admin_page = true
  end

  test 'should give warning for non-exising editable block' do
    skip 'This test does not work because the helper relies on the presence of current_ability'
    
    assert_equal 'Block not defined', display_block('pineapple', false)
  end

  test 'existing block should exist' do
    editable_block = FactoryBot.create :editable_block
    assert block_exists(editable_block.name)
  end

  test 'non-existing block should not exist' do
    assert_not block_exists('hexagon')
  end
end