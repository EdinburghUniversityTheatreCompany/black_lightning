class Admin::Form::TeamMembersComponentPreview < Admin::ApplicationComponentPreview
  # Team Members section on a Show form (includes bulk import link for Events)
  def default
    render_with_template(locals: { record: Show.first! })
  end

  # Team Members on a Proposal (no bulk import link)
  def proposal
    render_with_template(locals: { record: Admin::Proposals::Proposal.first! })
  end
end
