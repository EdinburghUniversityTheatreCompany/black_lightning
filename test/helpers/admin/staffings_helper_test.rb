require "test_helper"

class Admin::StaffingsHelperTest < ActionView::TestCase
  test "normal users cannot sign up" do
    # Member because they have access backend permission.
    user = FactoryBot.create(:member, phone_number: "12345")

    assert_not check_if_current_user_can_sign_up(user), "A normal user can sign up for staffing. Did you accidentally give them permission in the fixtures?"

    assert_equal [ "You do not have the appropriate permission to sign up for staffing slots." ], flash[:error]
  end

  test "member cannot sign up without phone number" do
    give_member_permission_to_sign_up_for_staffing
    member = users(:member)

    assert_not check_if_current_user_can_sign_up(member), "A member can sign up, even though they don't have a phone number set"

    assert_equal [ "You need to provide your phone number before you can sign up to staff." ], flash[:error]
  end

  test "members can sign up" do
    give_member_permission_to_sign_up_for_staffing
    member = FactoryBot.create(:member, phone_number: "12345")

    assert check_if_current_user_can_sign_up(member), "The member cannot sign up for staffing. Did you give them the permission using the helper method"

    assert_nil flash[:error]
  end

  test "members cannot sign up for committee rep and DM slots" do
    give_member_permission_to_sign_up_for_staffing

    member = users(:member_with_phone_number)

    assert_not check_if_current_user_can_sign_up(member, "DungeoN MasteR")
    assert_equal [ "You are not DM Trained. If you think this is a mistake, please contact the Theatre Manager." ], flash[:error]
    flash[:error] = nil

    assert_not check_if_current_user_can_sign_up(member, "comMittee reP")
    assert_equal [ "You are not on committee. If you think this is a mistake, please contact the Secretary." ], flash[:error]
  end

  test "members cannot sign up for bar slots" do
    give_member_permission_to_sign_up_for_staffing

    member = users(:member_with_phone_number)

    assert_not check_if_current_user_can_sign_up(member, "bar")
    assert_equal [ "You are not Bar Trained. If you think this is a mistake, please contact the Front of House Manager." ], flash[:error]
  end

  test "committee members can sign up for committee rep and DM slots" do
    committee = FactoryBot.create(:committee, phone_number: "123")

    assert check_if_current_user_can_sign_up(committee, "DuTy maNager")
    assert check_if_current_user_can_sign_up(committee, "comMittee reP")

    assert_nil flash[:error]
  end

  test "DM Trained users can sign up for DM slots" do
    give_member_permission_to_sign_up_for_staffing

    dm = users(:member_with_phone_number)
    dm.add_role "DM Trained"

    assert check_if_current_user_can_sign_up(dm, "DuTy maNager")

    assert_nil flash[:error]
  end

  test "DM Trained users cannot sign up for committee rep slots" do
    give_member_permission_to_sign_up_for_staffing

    dm = users(:member_with_phone_number)
    dm.add_role "DM Trained"

    assert_not check_if_current_user_can_sign_up(dm, "comMittee reP")
    assert_equal [ "You are not on committee. If you think this is a mistake, please contact the Secretary." ], flash[:error]
  end

  private

  def give_member_permission_to_sign_up_for_staffing
    Role.find_by(name: :member).permissions << Admin::Permission.create(action: "sign_up_for", subject_class: "Admin::StaffingJob")
  end
end
