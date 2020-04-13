require 'test_helper'

class Admin::EditableBlocksControllerTest < ActionController::TestCase
  setup do
    @admin_editable_block = admin_editable_blocks(:one)

    @user = FactoryBot.create(:admin)

    sign_in @user
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:admin_editable_blocks)
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create admin_editable_block' do
    # Remove the existing entry:
    Admin::EditableBlock.find(@admin_editable_block.id).destroy

    assert_difference('Admin::EditableBlock.count') do
      post :create, params: { admin_editable_block: { content: @admin_editable_block.content, name: @admin_editable_block.name } }
    end

    assert_redirected_to admin_editable_blocks_path
  end

  test 'should not create admin_editable_block that is invalid' do
    # Remove the existing entry:
    Admin::EditableBlock.find(@admin_editable_block.id).destroy
    @admin_editable_block.name = ''

    assert_no_difference('Admin::EditableBlock.count') do
      post :create, params: { admin_editable_block: { content: @admin_editable_block.content, name: @admin_editable_block.name } }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @admin_editable_block}
    assert_response :success
  end

  test 'should update admin_editable_block' do
    put :update, params: { id: @admin_editable_block, admin_editable_block: { content: @admin_editable_block.content, name: @admin_editable_block.name } }
    assert_redirected_to admin_editable_blocks_path
  end

  test 'should not update admin_editable_block that is invalid' do
    put :update, params: {id: @admin_editable_block, admin_editable_block: { content: @admin_editable_block.content, name: '' } }
    assert_response :unprocessable_entity
  end

  test 'should destroy admin_editable_block' do
    assert_difference('Admin::EditableBlock.count', -1) do
      delete :destroy, params: { id: @admin_editable_block }
    end

    assert_redirected_to admin_editable_blocks_path
  end
end
