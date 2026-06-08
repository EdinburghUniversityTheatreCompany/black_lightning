##
# Renders a single opportunity as a "project" with a sub-list of its roles.
#
# Used by the public opportunities listing and the home/dashboard widgets so the
# heading ("COMPANY: 'Project' by Author") and role list stay consistent.
#
# - +detailed+: show description, compensation/experience badges, apply link and
#   contact email (public listing). Widgets pass false for a compact view.
# - +heading_url+: when given, the heading links there (used by the widgets).
# - +backend_access+: whether the viewer may see members-only contact emails.
##
class OpportunityCardComponent < ViewComponent::Base
  def initialize(opportunity:, current_user: nil, backend_access: false, detailed: false, heading_url: nil)
    @opportunity = opportunity
    @current_user = current_user
    @backend_access = backend_access
    @detailed = detailed
    @heading_url = heading_url
  end

  private

  attr_reader :opportunity, :detailed, :heading_url

  # "COMPANY: 'Project' by Author", falling back to the title / display_title.
  def heading
    return opportunity.title if opportunity.title.present?

    project = opportunity.project.presence
    project = "'#{project}'" if project
    project = "#{project} by #{opportunity.author}" if project && opportunity.author.present?

    [ opportunity.company&.name, project ].compact_blank.join(": ").presence || opportunity.display_title
  end

  def roles
    opportunity.roles
  end

  def internal?
    opportunity.company&.internal
  end

  # Project-level badges worth surfacing (skip the "no signal" defaults).
  def compensation_label
    opportunity.compensation_type.humanize unless opportunity.compensation_tbc?
  end

  def experience_label
    opportunity.experience_level.humanize unless opportunity.experience_any?
  end

  def show_contact?
    opportunity.everyone? || (opportunity.members_only? && @backend_access)
  end

  def contact_email
    opportunity.resolved_contact_email
  end

  def submitter_name
    opportunity.submitter_display_name(@current_user)
  end
end
