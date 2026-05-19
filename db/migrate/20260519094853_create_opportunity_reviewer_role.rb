class CreateOpportunityReviewerRole < ActiveRecord::Migration[8.1]
  def up
    Role.find_or_create_by!(name: "Opportunity Reviewer")
  end

  def down
    Role.find_by(name: "Opportunity Reviewer")&.destroy
  end
end
