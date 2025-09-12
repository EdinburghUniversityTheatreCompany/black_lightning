require "test_helper"

class Admin::EditableBlockTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create :user
  end

  test "create debt" do
    debt = Admin::Debt.new(@user.id)
    assert_equal @user.id, debt.id
  end

  test "get oldest debt" do
    FactoryBot.create :maintenance_debt, user: @user, due_by: Date.current.advance(days: -15)
    FactoryBot.create :staffing_debt, user: @user, due_by: Date.current.advance(days: -5)

    assert_equal Date.current.advance(days: -15), Admin::Debt.users_oldest_debt(@user.id)
  end
end
