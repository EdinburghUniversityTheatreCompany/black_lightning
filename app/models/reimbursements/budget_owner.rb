# == Schema Information
#
# Table name: reimbursements_budget_owners
# Database name: primary
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  budget_id  :bigint           not null
#  person_id  :bigint           not null
#
# Indexes
#
#  index_reimbursements_budget_owners_on_budget_id                (budget_id)
#  index_reimbursements_budget_owners_on_budget_id_and_person_id  (budget_id,person_id) UNIQUE
#  index_reimbursements_budget_owners_on_person_id                (person_id)
#
# Foreign Keys
#
#  fk_rails_...  (budget_id => reimbursements_budgets.id)
#  fk_rails_...  (person_id => reimbursements_people.id)
#
module Reimbursements
  ##
  # Budget <-> People ownership (many-to-many; the Airtable "Owner" link).
  # Owners are payees, not user accounts — a budget owner may never log in.
  class BudgetOwner < ApplicationRecord
    belongs_to :budget, class_name: "Reimbursements::Budget", inverse_of: :budget_ownerships
    belongs_to :person, class_name: "Reimbursements::Person", inverse_of: :budget_ownerships

    validates :person_id, uniqueness: { scope: :budget_id }
  end
end
