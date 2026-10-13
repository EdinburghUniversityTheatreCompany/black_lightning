require "test_helper"

class UserImportTest < ActiveSupport::TestCase
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
    assert_empty import.rows
  end

  test "returns invalid with only header row" do
    tsv = "Name\tStudent ID\tEmail"

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_not import.valid?
    assert_empty import.rows
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

  test "categorizes fuzzy name match for active users only" do
    active_user = FactoryBot.create(:user, first_name: "John", last_name: "Smith")
    recent_show = FactoryBot.create(:show, start_date: Date.current - 1.month, end_date: Date.current - 1.month + 3.days)
    recent_show.team_members.create!(user: active_user, position: "Director")

    inactive_user = FactoryBot.create(:user, first_name: "Johnny", last_name: "Smith")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Jon Smith\t\t
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:fuzzy_match].size
    assert_includes import.categorized[:fuzzy_match].first[:existing_users], active_user
    assert_not_includes import.categorized[:fuzzy_match].first[:existing_users], inactive_user
  end

  test "prioritizes student_id match over email match" do
    user = FactoryBot.create(:user, student_id: "s1234567", email: "other@example.com")
    FactoryBot.create(:user, email: "test@example.com") # Different user with matching email

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\ts1234567\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:exact_match_id].size
    assert_equal user, import.categorized[:exact_match_id].first[:existing_user]
    assert_empty import.categorized[:exact_match_email]
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

    assert_equal existing_by_id, import.categorized[:exact_match_id].sole[:existing_user]
    assert_equal existing_by_email, import.categorized[:exact_match_email].sole[:existing_user]
    assert_nil import.categorized[:create_new].sole[:existing_user]
  end

  test "parses the user_id column under any of its headers" do
    user = FactoryBot.create(:user)

    [ "User ID", "user_id", "userid", "UserID" ].each do |header|
      tsv = <<~TSV
        #{header}\tName\tStudent ID\tEmail
        #{user.id}\tSome Name\ts9999999\tsome@example.com
      TSV

      import = UserImport.new(tsv, input_type: :paste, import_mode: :user)
      assert_equal user.id, import.rows.first[:user_id], header
    end
  end

  test "user_id is nil when column is absent" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Some Name\ts9999999\tsome@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)
    assert_nil import.rows.first[:user_id]
  end

  test "user_id is nil when value is blank" do
    tsv = <<~TSV
      User ID\tName\tStudent ID\tEmail
      \tSome Name\ts9999999\tsome@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)
    assert_nil import.rows.first[:user_id]
  end

  test "user_id match takes priority over student_id and email matches" do
    by_id = FactoryBot.create_list(:user, 2)
    FactoryBot.create(:user, student_id: "s8880001")
    FactoryBot.create(:user, email: "target@example.com")
    tsv = <<~TSV
      User ID\tName\tStudent ID\tEmail
      #{by_id[0].id}\tSome Name\ts8880001\tsome@example.com
      #{by_id[1].id}\tOther Name\ts9999999\ttarget@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal by_id, import.categorized[:exact_match_id].map { it[:existing_user] }
  end

  test "unknown user_id falls through to next matching strategy" do
    user = FactoryBot.create(:user, student_id: "s7654321")
    tsv = <<~TSV
      User ID\tName\tStudent ID\tEmail
      999999999\tSome Name\ts7654321\tsome@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)
    assert_equal 1, import.categorized[:exact_match_id].size
    assert_equal user, import.categorized[:exact_match_id].first[:existing_user]
  end

  test "returns multiple fuzzy match candidates sorted by confidence" do
    alex_exact = FactoryBot.create(:user, first_name: "Alex", last_name: "Kerr")
    alexander = FactoryBot.create(:user, first_name: "Alexander", last_name: "Kerr")

    recent_show = FactoryBot.create(:show, start_date: Date.current - 1.month, end_date: Date.current - 1.month + 3.days)
    recent_show.team_members.create!(user: alex_exact, position: "Director")
    recent_show.team_members.create!(user: alexander, position: "Producer")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Alex Kerr\t\t
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal 1, import.categorized[:fuzzy_match].size
    candidates = import.categorized[:fuzzy_match].first[:existing_users]
    assert_equal 2, candidates.size
    assert_equal alex_exact, candidates.first
    assert_equal alexander, candidates.second
  end

  test "mixed ID types across rows in same generic ID column" do
    user = FactoryBot.create(:user)
    tsv = <<~TSV
      Name\tID\tEmail
      Student Person\ts1234567\tstudent@example.com
      Associate Person\tASSOC42\tassoc@example.com
      Database Person\t#{user.id}\tdb@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_equal [
      { user_id: nil, student_id: "s1234567", associate_id: nil },
      { user_id: nil, student_id: nil, associate_id: "ASSOC42" },
      { user_id: user.id, student_id: nil, associate_id: nil }
    ], import.rows.map { it.slice(:user_id, :student_id, :associate_id) }
  end

  test "non-matching ID column headers like Transaction ID are ignored" do
    tsv = <<~TSV
      Name\tTransaction ID\tEmail
      Test User\t99999\ttest@example.com
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert_nil import.rows.first[:user_id]
    assert_nil import.rows.first[:student_id]
    assert_nil import.rows.first[:associate_id]
  end

  test "populates years_active_cache for fuzzy match candidates" do
    user = FactoryBot.create(:user, first_name: "John", last_name: "Smith")
    show = FactoryBot.create(:show, start_date: 1.month.ago.to_date, end_date: 1.month.ago.to_date + 3.days)
    show.team_members.create!(user: user, position: "Actor")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Jon Smith\t\t
    TSV

    import = UserImport.new(tsv, input_type: :paste, import_mode: :user)

    assert import.years_active_cache.key?(user.id)
    assert_includes import.years_active_cache[user.id], ApplicationController.helpers.date_to_academic_year(show.start_date)
  end
end
