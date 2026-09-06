require "test_helper"

##
# The writer is reached with a plain hash by every controller today, because
# `assign_attributes` deep-converts a permitted `Parameters` first. It is tested
# with `Parameters` as well because that conversion is the caller's, not ours: a
# caller that assigns `team_members_attributes=` directly hands the writer
# `Parameters`, and skipping the stamping there would drop the order silently —
# the failure this whole mechanism exists to prevent.
class TeamMemberOrderingTest < ActiveSupport::TestCase
  setup do
    @show = FactoryBot.create(:show)
    @users = FactoryBot.create_list(:member, 3)
  end

  def rows
    { "0" => { position: "Director", user_id: @users[0].id },
      "1" => { position: "Producer", user_id: @users[1].id },
      "2" => { position: "Stage Manager", user_id: @users[2].id } }
  end

  def saved_order
    @show.reload.team_members.ordered.pluck(:position, :display_order)
  end

  test "stamps the row order when assigned a plain hash" do
    @show.update!(team_members_attributes: rows)

    assert_equal [ [ "Director", 0 ], [ "Producer", 1 ], [ "Stage Manager", 2 ] ], saved_order
  end

  test "stamps the row order when assigned ActionController::Parameters" do
    params = ActionController::Parameters.new(team_members_attributes: rows)
                                         .permit(team_members_attributes: [ :position, :user_id ])

    @show.update!(team_members_attributes: params[:team_members_attributes])

    assert_equal [ [ "Director", 0 ], [ "Producer", 1 ], [ "Stage Manager", 2 ] ], saved_order
  end

  test "stamps the row order when assigned an array of rows" do
    @show.update!(team_members_attributes: rows.values)

    assert_equal [ [ "Director", 0 ], [ "Producer", 1 ], [ "Stage Manager", 2 ] ], saved_order
  end
end
