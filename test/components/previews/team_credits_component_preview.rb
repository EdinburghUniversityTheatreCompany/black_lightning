class TeamCreditsComponentPreview < ViewComponent::Preview
  # The public event page: no status badges unless you are in the teamwork.
  def default
    render TeamCreditsComponent.new(team_members: sample_members)
  end

  # The admin event page, where badges show for anyone the viewer can see.
  def on_the_admin_site
    render TeamCreditsComponent.new(team_members: sample_members, admin_site: true)
  end

  def empty
    render TeamCreditsComponent.new(team_members: TeamMember.none)
  end

  private

  def sample_members
    TeamMember.includes(:user).limit(10).to_a
  end
end
