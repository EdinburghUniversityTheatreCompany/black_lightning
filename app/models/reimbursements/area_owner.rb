# == Schema Information
#
# Table name: reimbursements_area_owners
# Database name: primary
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  area_id    :bigint           not null
#  person_id  :bigint           not null
#
# Indexes
#
#  index_reimbursements_area_owners_on_area_id                (area_id)
#  index_reimbursements_area_owners_on_area_id_and_person_id  (area_id,person_id) UNIQUE
#  index_reimbursements_area_owners_on_person_id              (person_id)
#
# Foreign Keys
#
#  fk_rails_...  (area_id => reimbursements_areas.id)
#  fk_rails_...  (person_id => reimbursements_people.id)
#
module Reimbursements
  ##
  # Area <-> People ownership (many-to-many).
  # Owners are payees, not user accounts — an area owner may never log in.
  class AreaOwner < ApplicationRecord
    self.table_name = "reimbursements_area_owners"

    belongs_to :area, class_name: "Reimbursements::Area", inverse_of: :area_ownerships
    belongs_to :person, class_name: "Reimbursements::Person"

    validates :person_id, uniqueness: { scope: :area_id }
  end
end
