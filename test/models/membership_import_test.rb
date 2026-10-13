require "test_helper"

class MembershipImportTest < ActiveSupport::TestCase
  setup do
    @member_with_student_id = FactoryBot.create(:member, student_id: "s1234567", email: "member@example.com")
    @non_member_with_student_id = FactoryBot.create(:user, student_id: "s7654321", email: "nonmember@example.com")
    @member_with_email = FactoryBot.create(:member, email: "existing@example.com")
    @non_member_with_email = FactoryBot.create(:user, email: "inactive@example.com")
    @user_with_similar_name = FactoryBot.create(:user, first_name: "John", last_name: "Smith")
  end

  test "parses valid TSV data" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tNew Person\t07/09/2025 14:25\tStudent\tnew@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.valid?
    assert_equal 1, import.rows.size
    assert_equal "New Person", import.rows.first[:original_name]
    assert_equal "New", import.rows.first[:first_name]
    assert_equal "Person", import.rows.first[:last_name]
    assert_equal "s9999999", import.rows.first[:student_id]
    assert_equal "new@example.com", import.rows.first[:email]
  end

  test "handles blank paste data" do
    import = MembershipImport.new("", input_type: :paste)

    assert_not import.valid?
    assert_equal 0, import.rows.size
  end

  test "handles TSV with only headers" do
    tsv = "Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email"

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_not import.valid?
    assert_equal 0, import.rows.size
  end

  test "student_id match takes priority over email match" do
    user = FactoryBot.create(:user, student_id: "s8888888", email: "priority@example.com")
    FactoryBot.create(:user, email: "different@email.com")

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s8888888\tTest User\t07/09/2025\tStudent\tdifferent@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal user, import.categorized[:activate_by_id].first[:existing_user]
    assert_empty import.categorized[:activate_by_email]
  end

  test "email match takes priority over name match" do
    user = FactoryBot.create(:user, first_name: "Bob", last_name: "Jones", email: "bob.jones@example.com")
    FactoryBot.create(:user, first_name: "Bobby", last_name: "Jones") # Similar name

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tRobert Jones\t07/09/2025\tStudent\tbob.jones@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:activate_by_email].size
    assert_equal user, import.categorized[:activate_by_email].first[:existing_user]
  end

  test "handles name with single word" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tMadonna\t07/09/2025\tStudent\tmadonna@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.valid?
    assert_equal "Madonna", import.rows.first[:first_name]
    assert_equal "", import.rows.first[:last_name]
  end

  test "handles name with multiple spaces" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tMary Jane Watson\t07/09/2025\tStudent\tmjw@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.valid?
    assert_equal "Mary", import.rows.first[:first_name]
    assert_equal "Jane Watson", import.rows.first[:last_name]
  end

  test "handles missing email" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tNo Email Person\t07/09/2025\tStudent\t
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.valid?
    assert_nil import.rows.first[:email]
  end

  test "handles mixed buckets in single import" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{@member_with_student_id.student_id}\tAlready Active\t07/09/2025\tStudent\talready@example.com
      #{@non_member_with_student_id.student_id}\tActivate By ID\t07/09/2025\tStudent\tactivate@example.com
      s9999998\tEmail Person\t07/09/2025\tStudent\t#{@non_member_with_email.email}
      s9999997\tJohnny Smith\t07/09/2025\tStudent\tjohnny@example.com
      s9999999\tBrand New\t07/09/2025\tStudent\tnew@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    categorized = import.categorized

    assert import.valid?
    assert_equal 5, import.rows.size
    assert_equal @member_with_student_id, categorized[:already_active].sole[:existing_user]
    assert_equal @non_member_with_student_id, categorized[:activate_by_id].sole[:existing_user]
    assert_equal @non_member_with_email, categorized[:activate_by_email].sole[:existing_user]
    assert_includes categorized[:propose_merge].sole[:existing_users], @user_with_similar_name
    assert_nil categorized[:create_new].sole[:existing_user]
  end

  test "normalizes email to lowercase" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tTest Person\t07/09/2025\tStudent\tTEST@EXAMPLE.COM
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal "test@example.com", import.rows.first[:email]
  end

  test "user_id match categorizes already-active member as already_active" do
    member = FactoryBot.create(:member)
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{member.id}\ts9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal 1, import.categorized[:already_active].size
    assert_equal member, import.categorized[:already_active].first[:existing_user]
  end

  test "user_id match takes priority over student_id, email and associate_id matches" do
    by_id = FactoryBot.create_list(:user, 3)
    FactoryBot.create(:user, student_id: "s8880001")
    FactoryBot.create(:user, email: "target@example.com")
    FactoryBot.create(:user, associate_id: "ASSOC8880001")
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{by_id[0].id}\ts8880001\tOne\t07/09/2025\tStudent\tone@example.com
      #{by_id[1].id}\ts9999999\tTwo\t07/09/2025\tStudent\ttarget@example.com
      #{by_id[2].id}\tASSOC8880001\tThree\t07/09/2025\tAssociate\tthree@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal by_id, import.categorized[:activate_by_id].map { it[:existing_user] }
  end

  test "unknown user_id falls through to next matching strategy" do
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      999999999\t#{@non_member_with_student_id.student_id}\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal @non_member_with_student_id, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "returns multiple fuzzy match candidates sorted by confidence" do
    alex_exact = FactoryBot.create(:user, first_name: "Alex", last_name: "Kerr")
    alexander = FactoryBot.create(:user, first_name: "Alexander", last_name: "Kerr")

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tAlex Kerr\t07/09/2025\tStudent\tnew@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:propose_merge].size
    candidates = import.categorized[:propose_merge].first[:existing_users]
    assert_equal 2, candidates.size
    assert_equal alex_exact, candidates.first
    assert_equal alexander, candidates.second
  end

  test "excludes users inactive for more than 5 years from fuzzy matching" do
    old_user = FactoryBot.create(:user, first_name: "John", last_name: "Ancient")
    old_show = FactoryBot.create(:show, start_date: Date.new(2015, 10, 1), end_date: Date.new(2015, 10, 5))
    old_show.team_members.create!(user: old_user, position: "Actor")

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tJohn Ancient\t07/09/2025\tStudent\tnew@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 0, import.categorized[:propose_merge].size
    assert_equal 1, import.categorized[:create_new].size
  end

  test "generic ID column works instead of Student ID header" do
    tsv = <<~TSV
      ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{@non_member_with_student_id.student_id}\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal @non_member_with_student_id, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "generic ID column with mixed ID types across rows" do
    associate_user = FactoryBot.create(:user, associate_id: "ASSOC999")
    numeric_user = FactoryBot.create(:user)

    tsv = <<~TSV
      ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{@non_member_with_student_id.student_id}\tStudent Person\t07/09/2025\tStudent\tstudent@example.com
      ASSOC999\tAssociate Person\t07/09/2025\tAssociate\tassoc@example.com
      #{numeric_user.id}\tDatabase Person\t07/09/2025\tStudent\tdb@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 3, import.categorized[:activate_by_id].size
  end

  test "populates years_active_cache for fuzzy match candidates" do
    user = FactoryBot.create(:user, first_name: "Alex", last_name: "Cached")
    show = FactoryBot.create(:show, start_date: 1.month.ago.to_date, end_date: 1.month.ago.to_date + 3.days)
    show.team_members.create!(user: user, position: "Actor")

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tAlex Cached\t07/09/2025\tStudent\tnew@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.years_active_cache.key?(user.id)
    assert_includes import.years_active_cache[user.id], ApplicationController.helpers.date_to_academic_year(show.start_date)
  end
end
