# The Cast / Production Team credits on an event's public and admin pages and on a
# proposal. Admin::Form::TeamMembersComponent is the editing side.
class TeamCreditsComponent < ViewComponent::Base
  # Status badges show to anyone in the teamwork; admin_site also shows them
  # for anyone the viewer may see.
  def initialize(team_members:, deadline: nil, admin_site: false)
    @team_members = team_members
    @deadline = deadline
    @admin_site = admin_site
  end

  private

  def cast_and_crew
    @cast_and_crew ||= @team_members.partition(&:cast?)
  end

  def cast = cast_and_crew.first
  def crew = cast_and_crew.last

  def show_badges_for?(team_member)
    return false if team_member.user.blank?

    part_of_teamwork? || (helpers.can?(:show, team_member.user) && @admin_site)
  end

  def part_of_teamwork?
    return @part_of_teamwork if defined?(@part_of_teamwork)

    @part_of_teamwork = @team_members.collect(&:user).include?(helpers.current_user)
  end

  def badges_for(team_member)
    helpers.team_member_labels_for(team_member, @deadline)
  end
end
