require "test_helper"

class MembershipImportTest < ActiveSupport::TestCase
  setup do
    # Create some test users
    @member_with_student_id = FactoryBot.create(:member, student_id: "s1234567", email: "member@example.com")
    @non_member_with_student_id = FactoryBot.create(:user, student_id: "s7654321", email: "nonmember@example.com")
    @member_with_email = FactoryBot.create(:member, email: "existing@example.com")
    @non_member_with_email = FactoryBot.create(:user, email: "inactive@example.com")
    @user_with_similar_name = FactoryBot.create(:user, first_name: "John", last_name: "Smith")
  end

  # TSV Parsing Tests

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

  test "parses TSV with associate ID" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      ASSOC123\tAssociate Member\t07/09/2025 14:25\tAssociate\tassoc@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.valid?
    assert_nil import.rows.first[:student_id]
    assert_equal "ASSOC123", import.rows.first[:associate_id]
  end

  test "parses TSV with multiple rows" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s1111111\tFirst Person\t07/09/2025\tStudent\tfirst@example.com
      s2222222\tSecond Person\t08/09/2025\tStudent\tsecond@example.com
      s3333333\tThird Person\t09/09/2025\tStudent\tthird@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.valid?
    assert_equal 3, import.rows.size
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

  # Categorization Tests

  test "categorizes already active member by student_id as already_active" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{@member_with_student_id.student_id}\tSome Name\t07/09/2025\tStudent\tsome@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:already_active].size
    assert_equal @member_with_student_id, import.categorized[:already_active].first[:existing_user]
  end

  test "categorizes non-member by student_id as activate_by_id" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{@non_member_with_student_id.student_id}\tSome Name\t07/09/2025\tStudent\tsome@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal @non_member_with_student_id, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "categorizes non-member by email as activate_by_email" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tSome Name\t07/09/2025\tStudent\t#{@non_member_with_email.email}
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:activate_by_email].size
    assert_equal @non_member_with_email, import.categorized[:activate_by_email].first[:existing_user]
  end

  test "categorizes fuzzy name match as propose_merge" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tJohnny Smith\t07/09/2025\tStudent\tnew@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:propose_merge].size
    assert_equal @user_with_similar_name, import.categorized[:propose_merge].first[:existing_user]
  end

  test "categorizes completely new user as create_new" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tCompletely New Person\t07/09/2025\tStudent\tbrandnew@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal 1, import.categorized[:create_new].size
    assert_nil import.categorized[:create_new].first[:existing_user]
  end

  test "student_id match takes priority over email match" do
    # Create a user with both student_id and email matching different import rows
    user = FactoryBot.create(:user, student_id: "s8888888", email: "priority@example.com")

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s8888888\tTest User\t07/09/2025\tStudent\tdifferent@email.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    # Should match by student_id, not create new despite different email
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal user, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "email match takes priority over name match" do
    # User with email that would match, and a name that could also fuzzy match
    user = FactoryBot.create(:user, first_name: "Bob", last_name: "Jones", email: "bob.jones@example.com")
    FactoryBot.create(:user, first_name: "Bobby", last_name: "Jones") # Similar name

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tRobert Jones\t07/09/2025\tStudent\tbob.jones@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    # Should match by email, not propose merge for name
    assert_equal 1, import.categorized[:activate_by_email].size
    assert_equal user, import.categorized[:activate_by_email].first[:existing_user]
  end

  # Edge Cases

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
      s9999999\tBrand New\t07/09/2025\tStudent\tnew@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert import.valid?
    assert_equal 3, import.rows.size
    assert_equal 1, import.categorized[:already_active].size
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal 1, import.categorized[:create_new].size
  end

  test "normalizes email to lowercase" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tTest Person\t07/09/2025\tStudent\tTEST@EXAMPLE.COM
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal "test@example.com", import.rows.first[:email]
  end

  test "normalizes student_id to lowercase" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      S1234567\tTest Person\t07/09/2025\tStudent\ttest@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal "s1234567", import.rows.first[:student_id]
  end

  test "normalizes associate_id to uppercase" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      assoc123\tTest Person\t07/09/2025\tAssociate\ttest@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)

    assert_equal "ASSOC123", import.rows.first[:associate_id]
  end

  # User ID Column Tests

  test "parses user_id column formatted as 'User ID'" do
    user = FactoryBot.create(:user)
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{user.id}\ts9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal user.id, import.rows.first[:user_id]
  end

  test "parses user_id column formatted as 'user_id'" do
    user = FactoryBot.create(:user)
    tsv = <<~TSV
      user_id\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{user.id}\ts9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal user.id, import.rows.first[:user_id]
  end

  test "parses user_id column formatted as 'userid'" do
    user = FactoryBot.create(:user)
    tsv = <<~TSV
      userid\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{user.id}\ts9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal user.id, import.rows.first[:user_id]
  end

  test "parses user_id column formatted as 'UserID'" do
    user = FactoryBot.create(:user)
    tsv = <<~TSV
      UserID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{user.id}\ts9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal user.id, import.rows.first[:user_id]
  end

  test "user_id is nil when column is absent" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_nil import.rows.first[:user_id]
  end

  test "user_id is nil when value is blank" do
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      \ts9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_nil import.rows.first[:user_id]
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

  test "user_id match categorizes non-member as activate_by_id" do
    non_member = FactoryBot.create(:user)
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{non_member.id}\ts9999999\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal non_member, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "user_id match takes priority over student_id match" do
    user_by_id  = FactoryBot.create(:user)
    user_by_sid = FactoryBot.create(:user, student_id: "s8880001")
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{user_by_id.id}\ts8880001\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal user_by_id, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "user_id match takes priority over email match" do
    user_by_id    = FactoryBot.create(:user)
    user_by_email = FactoryBot.create(:user, email: "target@example.com")
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{user_by_id.id}\ts9999999\tSome Name\t07/09/2025\tStudent\ttarget@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal user_by_id, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "user_id match takes priority over associate_id match" do
    user_by_id       = FactoryBot.create(:user)
    user_by_assoc_id = FactoryBot.create(:user, associate_id: "ASSOC8880001")
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      #{user_by_id.id}\tASSOC8880001\tSome Name\t07/09/2025\tAssociate\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal user_by_id, import.categorized[:activate_by_id].first[:existing_user]
  end

  test "unknown user_id falls through to next matching strategy" do
    tsv = <<~TSV
      User ID\tStudent ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      999999999\t#{@non_member_with_student_id.student_id}\tSome Name\t07/09/2025\tStudent\tsome@example.com
    TSV

    import = MembershipImport.new(tsv, input_type: :paste)
    # user_id 999999999 does not exist; falls through to student_id match
    assert_equal 1, import.categorized[:activate_by_id].size
    assert_equal @non_member_with_student_id, import.categorized[:activate_by_id].first[:existing_user]
  end
end
