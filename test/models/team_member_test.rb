require "test_helper"

class TeamMemberTest < ActiveSupport::TestCase
  include AcademicYearHelper

  test "should validate uniqueness in parent collection with nested attributes scenario" do
    event = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    # Both in memory, as when a form posts the same user twice.
    tm1 = event.team_members.build(user_id: user.id, position: "Director")
    tm2 = event.team_members.build(user_id: user.id, position: "Producer")

    assert tm1.valid?, "First team member should be valid"
    assert_not tm2.valid?, "Second team member should not be valid when user is already in collection"
    assert tm2.errors[:user_id].any? { |msg| msg.match?(/already a team member/) }, "Should have error message about duplicate"
  end

  test "a new event naming one person twice fails validation instead of hitting the unique index" do
    user = FactoryBot.create(:user)
    show = FactoryBot.build(:show, team_members_attributes: [
      { user_id: user.id, position: "Director" },
      { user_id: user.id, position: "Producer" }
    ])

    assert_no_difference "TeamMember.count" do
      assert_not show.save
    end
    first, second = show.team_members.to_a
    assert_empty first.errors[:user_id]
    assert second.errors[:user_id].any? { |msg| msg.include?("already a team member on this show") }
  end

  test "a new proposal naming one person twice fails validation instead of hitting the unique index" do
    user = FactoryBot.create(:user)
    proposal = FactoryBot.build(:proposal, team_members_attributes: [
      { user_id: user.id, position: "Director" },
      { user_id: user.id, position: "Producer" }
    ])

    assert_no_difference "TeamMember.count" do
      assert_not proposal.save
    end
    assert proposal.team_members.last.errors[:user_id].any? { |msg| msg.include?("already a team member on this proposal") }
  end

  test "a team member saved outside its teamwork's loaded rows is still checked against the database" do
    show = FactoryBot.create(:show, team_member_count: 1)
    existing = show.team_members.first
    show.team_members.build(user_id: existing.user_id, position: "Unsaved twin")

    outsider = TeamMember.new(teamwork: show, user_id: existing.user_id, position: "Producer")

    assert_not outsider.valid?
    assert outsider.errors[:user_id].present?
  end

  test "should allow same user on different events" do
    event1 = FactoryBot.create(:event)
    event2 = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    event1.team_members.create!(user_id: user.id, position: "Director")

    team_member2 = event2.team_members.build(user_id: user.id, position: "Producer")

    assert team_member2.valid?, "Should be valid when user is on different event"
  end

  test "should allow different users on same event" do
    event = FactoryBot.create(:event)
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    event.team_members.create!(user_id: user1.id, position: "Director")

    team_member2 = event.team_members.build(user_id: user2.id, position: "Producer")

    assert team_member2.valid?, "Should be valid when different user"
  end

  test "should work with Proposal which does not have STI type column" do
    proposal = FactoryBot.create(:proposal)
    user = FactoryBot.create(:user)

    # A Proposal has no type column, so no type_changed?.
    team_member = proposal.team_members.build(user_id: user.id, position: "Director")

    assert_nothing_raised { team_member.valid? }
  end

  test "should auto-create debts when added to show with debt configuration" do
    show = FactoryBot.create(:show,
      start_date: start_of_year,
      end_date: start_of_year.advance(days: 5),
      team_member_count: 0,
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14),
      staffing_debt_amount: 2,
      staffing_debt_start: Date.current.advance(days: 14)
    )
    user = FactoryBot.create(:user)

    assert_difference "Admin::MaintenanceDebt.count", 1 do
      assert_difference "Admin::StaffingDebt.count", 2 do
        show.team_members.create!(user_id: user.id, position: "Director")
      end
    end

    assert_equal 1, user.admin_maintenance_debts.where(show: show).count
    assert_equal 2, user.admin_staffing_debts.where(show: show).count
  end

  test "should not create debts when added to show without debt configuration" do
    show = FactoryBot.create(:show, team_member_count: 0)
    user = FactoryBot.create(:user)

    assert_no_difference [ "Admin::MaintenanceDebt.count", "Admin::StaffingDebt.count" ] do
      show.team_members.create!(user_id: user.id, position: "Director")
    end
  end

  test "should not create debts when added to non-show teamwork" do
    workshop = FactoryBot.create(:workshop, start_date: start_of_year, end_date: start_of_year.advance(days: 5),
                                            maintenance_debt_amount: 1, maintenance_debt_start: Date.current,
                                            staffing_debt_amount: 2, staffing_debt_start: Date.current)

    assert_no_difference [ "Admin::MaintenanceDebt.count", "Admin::StaffingDebt.count" ] do
      workshop.team_members.create!(user: FactoryBot.create(:user), position: "Director")
    end
  end

  test "cast? reads an Actor or Cast segment anywhere in the position" do
    { "Actor (King)" => true, "Cast (King)" => true, "aCtor ( King ) " => true, "CAST ( Queen ) " => true,
      "Actor (The King) / Stage Manager" => true, "Actor (Gustave/Franz)" => true,
      "Director" => false, "Tech Manager / Lighting Designer" => false }.each do |position, expected|
      assert_equal expected, TeamMember.new(position: position).cast?, position
    end
  end

  test "cast_display_name" do
    { "Actor (King)" => "King", "Cast (King)" => "King", "aCtor ( King ) " => "King",
      "Actor (The King, The Beggar)" => "The King, The Beggar", "Actor (Gustave/Franz)" => "Gustave/Franz",
      "Actor (The King) / Stage Manager" => "The King / Crew<wbr>(Stage Manager)</wbr>",
      "Actor (King) / Sound Designer / Lighting Designer" =>
        "King / Crew<wbr>(Sound Designer, Lighting Designer)</wbr>" }.each do |position, expected|
      assert_equal expected, TeamMember.new(position: position).cast_display_name, position
    end
  end

  # ordered scope

  test "ordered sorts by display_order, nulls last, then by name" do
    numbered = %i[ordered_first ordered_second ordered_null].map { |name| team_members(name).id }
    unnumbered = %i[alpha_first alpha_last].map { |name| team_members(name).id }

    assert_equal numbered, TeamMember.where(id: numbered).ordered.ids
    assert_equal unnumbered, TeamMember.where(id: unnumbered).ordered.ids
  end

  test "in_display_order agrees with the ordered scope" do
    members = TeamMember.where(teamwork_id: [ 9001, 9002 ], teamwork_type: "Event")

    assert_equal members.ordered.map(&:id), TeamMember.in_display_order(members.to_a.shuffle).map(&:id)
  end

  # The form sorts in Ruby, the page in MySQL, whose collation folds accents.
  test "in_display_order agrees with the ordered scope on accented names" do
    show = FactoryBot.create(:show)
    abel = FactoryBot.create(:team_member, teamwork: show, position: "Sound",
                             user: FactoryBot.create(:member, first_name: "Ábel", last_name: "Nagy"))
    bob = FactoryBot.create(:team_member, teamwork: show, position: "Lighting",
                            user: FactoryBot.create(:member, first_name: "Bob", last_name: "Smith"))

    assert_equal [ abel.id, bob.id ], show.team_members.ordered.ids
    assert_equal [ abel.id, bob.id ], TeamMember.in_display_order([ bob, abel ]).map(&:id)
  end

  test "in_display_order sorts unsaved rows with no display_order last" do
    ordered = team_members(:ordered_first)
    added = TeamMember.new(position: "Sound", user: users(:user))

    assert_equal [ ordered, added ], TeamMember.in_display_order([ added, ordered ])
  end

  # display_order for rows written outside the form

  test "rows are numbered in creation order, a later row landing at the end" do
    show = FactoryBot.create(:show)
    show.team_members.create!(user: FactoryBot.create(:user), position: "Director")
    show.team_members.create!(user: FactoryBot.create(:user), position: "Producer")
    TeamMember.create!(teamwork: show, user: FactoryBot.create(:user), position: "Proposer")

    assert_equal [ [ "Director", 0 ], [ "Producer", 1 ], [ "Proposer", 2 ] ],
                 show.team_members.ordered.pluck(:position, :display_order)
  end

  # The max + 1 trap: on an all-nil teamwork the new row would take 0 and, as
  # NULLs sort last, jump ABOVE every existing row.
  test "a row added to an unnumbered teamwork stays unnumbered" do
    show = FactoryBot.create(:show)
    zoe = FactoryBot.create(:user, first_name: "Zoe", last_name: "Zebra")
    amy = FactoryBot.create(:user, first_name: "Amy", last_name: "Apple")
    legacy = show.team_members.create!(user: zoe, position: "Director")
    legacy.update_columns(display_order: nil)

    added = show.team_members.create!(user: amy, position: "Producer")

    assert_nil added.reload.display_order
    assert_equal [ added, legacy ], show.team_members.ordered.to_a
  end

  test "an explicit display_order is never overwritten" do
    show = FactoryBot.create(:show)
    member = show.team_members.create!(user: FactoryBot.create(:user), position: "Director",
                                       display_order: 7)

    assert_equal 7, member.reload.display_order
  end

  # As imports.rake builds them.
  test "rows built on an unsaved teamwork stay unnumbered" do
    show = FactoryBot.build(:show, team_members: [
      TeamMember.new(user: FactoryBot.create(:user), position: "Director"),
      TeamMember.new(user: FactoryBot.create(:user), position: "Producer")
    ])
    show.save!

    assert_equal [ nil, nil ], show.team_members.reload.map(&:display_order)
  end
end
