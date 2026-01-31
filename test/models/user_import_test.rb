require "test_helper"

class UserImportTest < ActiveSupport::TestCase
  # Parsing tests

  test "parses TSV data correctly" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Finbar Viking\ts1234567\tfinbar@viking.se
      Erik Bloodaxe\t\terik@norse.no
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert import.valid?
    assert_equal 2, import.rows.size

    assert_equal "Finbar Viking", import.rows[0][:original_name]
    assert_equal "Finbar", import.rows[0][:first_name]
    assert_equal "Viking", import.rows[0][:last_name]
    assert_equal "s1234567", import.rows[0][:student_id]
    assert_equal "finbar@viking.se", import.rows[0][:email]

    assert_equal "Erik Bloodaxe", import.rows[1][:original_name]
    assert_nil import.rows[1][:student_id]
    assert_equal "erik@norse.no", import.rows[1][:email]
  end

  test "normalizes student_id to lowercase" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\tS1234567\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal "s1234567", import.rows[0][:student_id]
  end

  test "normalizes associate_id to uppercase" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\tassoc123\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal "ASSOC123", import.rows[0][:associate_id]
  end

  test "auto-generates email from student_id when email is blank" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\ts1234567\t
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal "s1234567@ed.ac.uk", import.rows[0][:email]
  end

  test "does not auto-generate email for associate_id" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\tASSOC123\t
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_nil import.rows[0][:email]
  end

  test "parses position column for crew import mode" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail\tPosition
      Test User\ts1234567\ttest@example.com\tDirector
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :crew)

    assert_equal "Director", import.rows[0][:position]
  end

  test "does not include position for user import mode" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail\tPosition
      Test User\ts1234567\ttest@example.com\tDirector
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_not import.rows[0].key?(:position)
  end

  test "returns invalid with empty data" do
    import = UserImport.new("", input_type: :paste, import_mode: :user)

    assert_not import.valid?
    assert import.rows.empty?
  end

  test "returns invalid with only header row" do
    tsv = "Name\tStudent ID\tEmail"

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_not import.valid?
    assert import.rows.empty?
  end

  # Categorization tests

  test "categorizes exact match by student_id" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\ts1234567\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:exact_match_id].size
    assert_equal user, import.categorized[:exact_match_id].first[:existing_user]
  end

  test "categorizes exact match by associate_id" do
    user = FactoryBot.create(:user, associate_id: "ASSOC123")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\tASSOC123\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:exact_match_id].size
    assert_equal user, import.categorized[:exact_match_id].first[:existing_user]
  end

  test "categorizes exact match by email" do
    user = FactoryBot.create(:user, email: "test@example.com")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\t\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:exact_match_email].size
    assert_equal user, import.categorized[:exact_match_email].first[:existing_user]
  end

  test "categorizes fuzzy name match for active users only" do
    # Create an active user (with team membership on recent event)
    active_user = FactoryBot.create(:user, first_name: "John", last_name: "Smith")
    recent_show = FactoryBot.create(:show, start_date: Date.current - 1.month, end_date: Date.current - 1.month + 3.days)
    recent_show.team_members.create!(user: active_user, position: "Director")

    # Create an inactive user with same last name
    inactive_user = FactoryBot.create(:user, first_name: "Johnny", last_name: "Smith")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Jon Smith\t\t
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    # Should fuzzy match the active user, not the inactive one
    assert_equal 1, import.categorized[:fuzzy_match].size
    assert_equal active_user, import.categorized[:fuzzy_match].first[:existing_user]
  end

  test "categorizes as create_new when no match found" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Brand New User\ts9999999\tnew@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:create_new].size
    assert_nil import.categorized[:create_new].first[:existing_user]
  end

  test "prioritizes student_id match over email match" do
    user = FactoryBot.create(:user, student_id: "s1234567", email: "other@example.com")
    FactoryBot.create(:user, email: "test@example.com") # Different user with matching email

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\ts1234567\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    # Should match by student_id, not email
    assert_equal 1, import.categorized[:exact_match_id].size
    assert_equal user, import.categorized[:exact_match_id].first[:existing_user]
    assert import.categorized[:exact_match_email].empty?
  end

  test "handles multiple rows with different categorizations" do
    existing_by_id = FactoryBot.create(:user, student_id: "s1111111")
    existing_by_email = FactoryBot.create(:user, email: "existing@example.com")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      User One\ts1111111\tone@example.com
      User Two\t\texisting@example.com
      User Three\ts3333333\tnew@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:exact_match_id].size
    assert_equal 1, import.categorized[:exact_match_email].size
    assert_equal 1, import.categorized[:create_new].size
  end
end
