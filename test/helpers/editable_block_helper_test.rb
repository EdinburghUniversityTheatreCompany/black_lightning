require 'test_helper'

class EditableBlockHelperTest < ActionView::TestCase
  def current_ability
    users(:admin).ability
  end

  test 'should display editable block' do
    editable_block = FactoryBot.create :editable_block

    assert_raises ActionView::Template::Error do
      display_block(editable_block.name, false)
    end
  end

  test 'displaying block on admin page should set to admin page to true' do
    editable_block = FactoryBot.create(:editable_block, admin_page: false)

    assert_raises ActionView::Template::Error do
      display_block(editable_block.name, true)
    end

    assert editable_block.reload.admin_page
  end

  test 'should give warning for non-exising editable block' do
    assert_equal 'Block not defined. <a class="btn btn-primary my-1 mr-1" title="Create Editable Block" data-method="get" href="/admin/editable_blocks/new?name=pineapple"><span class="no-wrap"><i class="fas fa-align-left" aria-hidden=”true”></i> Create Editable Block</span></a>', display_block('pineapple', false)
  end

  test 'existing block should exist' do
    editable_block = FactoryBot.create :editable_block
    assert block_exists?(editable_block.name)
  end

  test 'non-existing block should not exist' do
    assert_not block_exists?('hexagon')
  end
end
