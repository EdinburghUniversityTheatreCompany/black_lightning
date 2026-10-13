require "test_helper"

class Admin::DebtCheckersControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "non-admin cannot access" do
    sign_out users(:admin)
    sign_in users(:member)

    get :new
    assert_response :forbidden
  end

  { "producer on a future show" => [ 1.week, "Producer", :success ],
    "producer on a past show" => [ -2.months, "Producer", :forbidden ],
    "non-producer on a future show" => [ 1.week, "Director", :forbidden ] }.each do |who, (offset, position, status)|
    test "#{who} gets #{status} from debt checker" do
      sign_out users(:admin)
      start = Date.current + offset
      show = FactoryBot.create(:show, start_date: start, end_date: start + 1.week)
      user = FactoryBot.create(:member)
      FactoryBot.create(:team_member, user: user, teamwork: show, position: position)

      sign_in user
      get :new
      assert_response status
    end
  end

  test "preview with valid paste data shows results" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\ts1234567\ttest@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_equal 1, assigns(:exact_matches).size
    assert_equal user, assigns(:exact_matches).first[:user]
  end

  test "preview with empty data redirects back with error" do
    post :preview, params: { paste_data: "" }

    assert_redirected_to new_admin_debt_checker_path
    assert flash[:error].present?
  end

  test "preview shows unmatched people" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Nobody Here\ts0000000\tnobody@example.com
      Person Two\t\t
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_equal 2, assigns(:unmatched).size
    assert_equal 0, assigns(:exact_matches).size
    assert_match "Checked 2 row(s)", response.body
  end

  test "preview shows debt status for matched users" do
    user_in_debt = FactoryBot.create(:member, student_id: "s1111111")
    user_not_in_debt = FactoryBot.create(:member, student_id: "s2222222")

    show = FactoryBot.create(:show)
    FactoryBot.create(:maintenance_debt,
      user: user_in_debt,
      show: show,
      due_by: 1.day.ago
    )

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Debtor\ts1111111\t
      Clean\ts2222222\t
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_equal 2, assigns(:exact_matches).size
    assert_includes assigns(:in_debt_ids), user_in_debt.id
    refute_includes assigns(:in_debt_ids), user_not_in_debt.id
  end

  test "preview shows membership status" do
    member_user = FactoryBot.create(:member, student_id: "s3333333")
    non_member_user = FactoryBot.create(:user, student_id: "s4444444")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Member\ts3333333\t
      Non-member\ts4444444\t
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_includes assigns(:member_ids), member_user.id
    refute_includes assigns(:member_ids), non_member_user.id
  end

  test "preview matches by email" do
    user = FactoryBot.create(:user, email: "known@example.com")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Someone\t\tknown@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_equal 1, assigns(:exact_matches).size
    assert_equal "Email", assigns(:exact_matches).first[:match_type]
  end
end
