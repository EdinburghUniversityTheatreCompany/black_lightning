require "application_system_test_case"

class TomSelectHelperTest < ApplicationSystemTestCase
  test "tom_select picks an option whose text contains an apostrophe" do
    user = FactoryBot.create(:user, first_name: "Conan", last_name: "O'Brien")
    login_as users(:admin)
    visit new_admin_maintenance_credit_path

    tom_select user.name, from: "User"

    assert_equal user.id.to_s, find("select[name$='[user_id]']", visible: :all).value
  end
end
