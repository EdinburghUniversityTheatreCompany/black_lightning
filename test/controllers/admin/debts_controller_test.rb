require 'test_helper'

class Admin::DebtsControllerTest < ActionController::TestCase
  setup do
    @admin = FactoryBot.create(:admin)
    sign_in @admin
    @member = FactoryBot.create(:member)
  end

  test 'should get index' do
    get :index
    assert_response :success

    assert User.with_role(:member).all.to_a & assigns(:users).to_a == assigns(:users).to_a
  end

  test 'should get index with only in debt' do
    FactoryBot.create(:overdue_staffing_debt, user: @member)

    get :index, params: { show_in_debt_only: 1 }
    assert_response :success

    assert assigns(:users).to_a.include? @member
    assert_not assigns(:users).to_a.include? @admin
  end

  test 'should get show' do
    get :show, params: { id: @member.id }
    assert_response :success
  end
end
