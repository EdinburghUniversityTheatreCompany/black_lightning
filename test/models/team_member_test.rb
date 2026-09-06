require "test_helper"

class TeamMemberTest < ActiveSupport::TestCase
  include AcademicYearHelper

  test "should validate uniqueness in parent collection with nested attributes scenario" do
    event = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    # Build BOTH team members in memory (simulates nested attributes)
    # This is what happens when form submits same user twice with different positions
    tm1 = event.team_members.build(user_id: user.id, position: "Director")
    tm2 = event.team_members.build(user_id: user.id, position: "Producer")

    # The first one should be valid
    assert tm1.valid?, "First team member should be valid"

    # The second one should be invalid (duplicate user in collection)
    assert_not tm2.valid?, "Second team member should not be valid when user is already in collection"
    assert tm2.errors[:user_id].any? { |msg| msg.match?(/already a team member/) }, "Should have error message about duplicate"
  end

  test "should allow same user on different events" do
    event1 = FactoryBot.create(:event)
    event2 = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    # Create team member on first event
    event1.team_members.create!(user_id: user.id, position: "Director")

    # Should allow same user on different event
    team_member2 = event2.team_members.build(user_id: user.id, position: "Producer")

    assert team_member2.valid?, "Should be valid when user is on different event"
  end

  test "should allow different users on same event" do
    event = FactoryBot.create(:event)
    user1 = FactoryBot.create(:user)
    user2 = FactoryBot.create(:user)

    # Create first team member
    event.team_members.create!(user_id: user1.id, position: "Director")

    # Should allow different user
    team_member2 = event.team_members.build(user_id: user2.id, position: "Producer")

    assert team_member2.valid?, "Should be valid when different user"
  end

  test "should work with Proposal which does not have STI type column" do
    proposal = FactoryBot.create(:proposal)
    user = FactoryBot.create(:user)

    # Build a team member on a Proposal (non-STI model)
    # This should not raise NoMethodError for type_changed?
    team_member = proposal.team_members.build(user_id: user.id, position: "Director")

    # Should be able to validate without error
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

    assert_no_difference "Admin::MaintenanceDebt.count" do
      assert_no_difference "Admin::StaffingDebt.count" do
        show.team_members.create!(user_id: user.id, position: "Director")
      end
    end
  end

  test "should not create debts when added to non-show teamwork" do
    event = FactoryBot.create(:event)
    user = FactoryBot.create(:user)

    assert_no_difference "Admin::MaintenanceDebt.count" do
      assert_no_difference "Admin::StaffingDebt.count" do
        event.team_members.create!(user_id: user.id, position: "Director")
      end
    end
  end

  # cast? and cast_display_name

  test "cast? is true for Actor position" do
    assert TeamMember.new(position: "Actor (King)").cast?
  end

  test "cast? is true for Cast position" do
    assert TeamMember.new(position: "Cast (King)").cast?
  end

  test "cast? is true for Actor position with loose casing and whitespace" do
    assert TeamMember.new(position: "aCtor ( King ) ").cast?
  end

  test "cast? is true for Cast position with loose casing" do
    assert TeamMember.new(position: "CAST ( Queen ) ").cast?
  end

  test "cast? is true when Actor is first of multiple segments" do
    assert TeamMember.new(position: "Actor (The King) / Stage Manager").cast?
  end

  test "cast? is false for crew-only position" do
    assert_not TeamMember.new(position: "Director").cast?
  end

  test "cast? is false for multi-role crew position" do
    assert_not TeamMember.new(position: "Tech Manager / Lighting Designer").cast?
  end

  test "cast_display_name returns role name for simple actor" do
    assert_equal "King", TeamMember.new(position: "Actor (King)").cast_display_name
  end

  test "cast_display_name returns role name for Cast keyword" do
    assert_equal "King", TeamMember.new(position: "Cast (King)").cast_display_name
  end

  test "cast_display_name strips whitespace from role name" do
    assert_equal "King", TeamMember.new(position: "aCtor ( King ) ").cast_display_name
  end

  test "cast_display_name returns multiple character names as comma list" do
    assert_equal "The King, The Beggar", TeamMember.new(position: "Actor (The King, The Beggar)").cast_display_name
  end

  test "cast_display_name appends crew roles with Crew () wrapper" do
    assert_equal "The King / Crew<wbr>(Stage Manager)</wbr>", TeamMember.new(position: "Actor (The King) / Stage Manager").cast_display_name
  end

  test "cast_display_name handles multiple crew roles" do
    assert_equal "King / Crew<wbr>(Sound Designer, Lighting Designer)</wbr>", TeamMember.new(position: "Actor (King) / Sound Designer / Lighting Designer").cast_display_name
  end

  test "cast? is true when actor name contains a slash" do
    assert TeamMember.new(position: "Actor (Gustave/Franz)").cast?
  end

  test "cast_display_name returns role name containing a slash" do
    assert_equal "Gustave/Franz", TeamMember.new(position: "Actor (Gustave/Franz)").cast_display_name
  end

  # ordered scope

  test "ordered scope sorts by display_order with nulls last" do
    first_id  = team_members(:ordered_first).id
    second_id = team_members(:ordered_second).id
    null_id   = team_members(:ordered_null).id

    ordered = TeamMember.where(id: [ first_id, second_id, null_id ]).ordered
    assert_equal [ first_id, second_id, null_id ], ordered.map(&:id)
  end

  test "in_display_order agrees with the ordered scope" do
    members = TeamMember.where(teamwork_id: [ 9001, 9002 ], teamwork_type: "Event")

    assert_equal members.ordered.map(&:id), TeamMember.in_display_order(members.to_a.shuffle).map(&:id)
  end

  # The form sorts in Ruby and the public page in MySQL, whose collation
  # (utf8mb4_unicode_ci) folds accents. If the two disagree, the form shows one
  # order, the page another, and the first save through the form makes the
  # form's order permanent.
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

  test "ordered scope sorts null display_order records alphabetically by name" do
    alpha_id = team_members(:alpha_first).id
    last_id  = team_members(:alpha_last).id

    ordered = TeamMember.where(id: [ alpha_id, last_id ]).ordered
    assert_equal [ alpha_id, last_id ], ordered.map(&:id)
  end

  # --- display_order for rows written outside the form -----------------------
  #
  # TeamMemberOrdering only numbers rows that come through
  # team_members_attributes=. The bulk crew import, the "Proposer" row and
  # lib/tasks/imports.rake all create rows directly, so those sorted to the
  # bottom by name rather than in the order they were imported.

  test "rows created on an empty teamwork are numbered in creation order" do
    show = FactoryBot.create(:show)
    first = show.team_members.create!(user: FactoryBot.create(:user), position: "Director")
    second = show.team_members.create!(user: FactoryBot.create(:user), position: "Producer")

    assert_equal 0, first.reload.display_order
    assert_equal 1, second.reload.display_order
    assert_equal [ first, second ], show.team_members.ordered.to_a
  end

  test "a row appended to a numbered teamwork lands at the end" do
    show = FactoryBot.create(:show)
    show.team_members.create!(user: FactoryBot.create(:user), position: "Director")
    show.team_members.create!(user: FactoryBot.create(:user), position: "Producer")

    proposer = TeamMember.create!(teamwork: show, user: FactoryBot.create(:user), position: "Proposer")

    assert_equal 2, proposer.reload.display_order
    assert_equal proposer, show.team_members.ordered.last
  end

  # The trap in the obvious `display_order ||= max + 1`: on an all-nil teamwork
  # `max` is nil, so the new row takes 0 -- and since NULLs sort last it jumps
  # ABOVE every existing row instead of appending to them.
  test "a row added to an unnumbered teamwork stays unnumbered" do
    show = FactoryBot.create(:show)
    zoe = FactoryBot.create(:user, first_name: "Zoe", last_name: "Zebra")
    amy = FactoryBot.create(:user, first_name: "Amy", last_name: "Apple")
    legacy = show.team_members.create!(user: zoe, position: "Director")
    legacy.update_columns(display_order: nil)

    added = show.team_members.create!(user: amy, position: "Producer")

    assert_nil added.reload.display_order
    # Both unnumbered, so the whole list stays in name order rather than the
    # newest row leaping to the top.
    assert_equal [ added, legacy ], show.team_members.ordered.to_a
  end

  test "an explicit display_order is never overwritten" do
    show = FactoryBot.create(:show)
    member = show.team_members.create!(user: FactoryBot.create(:user), position: "Director",
                                       display_order: 7)

    assert_equal 7, member.reload.display_order
  end

  # imports.rake builds rows against a Show that has not been saved yet, so
  # there is no teamwork to count siblings on. Archive rows are name-ordered
  # anyway, which is what an unnumbered teamwork gives.
  test "rows built on an unsaved teamwork stay unnumbered" do
    show = FactoryBot.build(:show, team_members: [
      TeamMember.new(user: FactoryBot.create(:user), position: "Director"),
      TeamMember.new(user: FactoryBot.create(:user), position: "Producer")
    ])
    show.save!

    assert_equal [ nil, nil ], show.team_members.reload.map(&:display_order)
  end
end
