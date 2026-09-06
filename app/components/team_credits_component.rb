# The Cast / Production Team credits, rendered on an event's public page, the
# admin event page and a proposal. Named for what it shows rather than where it
# shows it: the old partial was shared/_admin_show_team_members, which reads as
# admin-only and is rendered on the public event page. Distinct from
# Admin::Form::TeamMembersComponent, which is the editing side.
class TeamCreditsComponent < ViewComponent::Base
  # admin_site was an @admin_site read from inside the markup. It only widens
  # who sees the status badges: anyone in the teamwork sees them on their
  # collaborators wherever they are, and on the admin site they also show for
  # anyone the viewer is allowed to see.
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
