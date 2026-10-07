require "test_helper"

##
# Parameters as well as a plain hash: update deep-converts it, but a caller
# assigning team_members_attributes= directly passes Parameters, and its order
# must not drop silently.
class TeamMemberOrderingTest < ActiveSupport::TestCase
  setup do
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

  test "stamps the row order whatever shape the rows arrive in" do
    params = ActionController::Parameters.new(team_members_attributes: rows)
                                         .permit(team_members_attributes: [ :position, :user_id ])

    { hash: rows, parameters: params[:team_members_attributes], array: rows.values }.each do |shape, attributes|
      @show = FactoryBot.create(:show)
      @show.update!(team_members_attributes: attributes)

      assert_equal [ [ "Director", 0 ], [ "Producer", 1 ], [ "Stage Manager", 2 ] ], saved_order, shape
    end
  end
end
