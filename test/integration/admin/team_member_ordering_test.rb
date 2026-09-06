require "test_helper"

##
# See TeamMemberOrdering. An integration test rather than a functional one: a row
# added with "Add" posts under a timestamp key, and ActionController::TestCase
# encodes params with Hash#to_query, which SORTS keys. rack-test keeps the
# insertion order, as a browser serialises a form.
class Admin::TeamMemberOrderingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:admin) }

  def team_member_row(member)
    { id: member.id, user_id: member.user_id, position: member.position, _destroy: "false" }
  end

  test "a team member added between two rows is numbered by where it was added" do
    show = FactoryBot.create(:show, team_member_count: 2)
    a, b = show.team_members.order(:id).to_a
    newcomer = FactoryBot.create(:member)

    patch admin_show_path(show), params: { show: { team_members_attributes: {
      "0" => team_member_row(a),
      "1760000000000" => { user_id: newcomer.id, position: "Sound Designer" },
      "1" => team_member_row(b)
    } } }
    assert_redirected_to admin_show_path(show)

    assert_equal [ [ a.user_id, 0 ], [ newcomer.id, 1 ], [ b.user_id, 2 ] ],
                 show.team_members.ordered.pluck(:user_id, :display_order)
  end

  test "rows keep the order they were posted in, whatever their keys" do
    show = FactoryBot.create(:show, team_member_count: 3)
    a, b, c = show.team_members.order(:id).to_a

    patch admin_show_path(show), params: { show: { team_members_attributes: {
      "2" => team_member_row(c),
      "0" => team_member_row(a),
      "1" => team_member_row(b)
    } } }
    assert_redirected_to admin_show_path(show)

    assert_equal [ c.id, a.id, b.id ], show.team_members.ordered.ids
  end
end
