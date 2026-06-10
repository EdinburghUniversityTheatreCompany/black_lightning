class OpportunityCardComponentPreview < ViewComponent::Preview
  # Full, detailed card as shown on the public opportunities listing.
  def detailed
    render OpportunityCardComponent.new(opportunity: sample_opportunity, detailed: true, backend_access: true)
  end

  # Compact card with a linked heading, as shown in the home/dashboard widgets.
  def compact
    render OpportunityCardComponent.new(opportunity: sample_opportunity, heading_url: "/get_involved/opportunities")
  end

  # An explicit-title posting with no company/project and no roles.
  def title_only
    opportunity = Opportunity.new(
      title: "General stage crew wanted",
      description: "We need extra hands for get-in week.",
      expiry_date: 2.weeks.from_now,
      compensation_type: :unpaid,
      experience_level: :any
    )
    render OpportunityCardComponent.new(opportunity: opportunity, detailed: true)
  end

  private

  def sample_opportunity
    company = Company.new(name: "Gutter Theatre", internal: true)
    Opportunity.new(
      description: "An exciting production looking for a full crew.",
      project: "Eurydice",
      author: "Sarah Ruhl",
      expiry_date: 3.weeks.from_now,
      company: company,
      compensation_type: :expenses_only,
      experience_level: :student,
      contact_email: "casting@example.com",
      email_visibility: :everyone,
      apply_url: "https://example.com/apply",
      submitter_name: "Jane Director",
      submitter_email: "jane@example.com",
      roles: [
        OpportunityRole.new(position: "Stage Manager", department: Department.new(name: "Stage Management"), ordering: 0),
        OpportunityRole.new(position: "Set Manager", department: Department.new(name: "Set"), note: "Build weekends only", ordering: 1),
        OpportunityRole.new(position: "Sound Technician", department: Department.new(name: "Sound"), ordering: 2)
      ]
    )
  end
end
