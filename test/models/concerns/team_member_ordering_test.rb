require "test_helper"

##
# Parameters as well as a plain hash: update deep-converts it, but a caller
# assigning team_members_attributes= directly passes Parameters, and its order
# must not drop silently.
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
