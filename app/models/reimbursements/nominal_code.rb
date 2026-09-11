# == Schema Information
#
# Table name: reimbursements_nominal_codes
# Database name: primary
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(TRUE), not null
#  code           :string(255)      not null
#  label          :string(255)      not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  cost_centre_id :bigint           not null
#
# Indexes
#
#  index_reimbursements_nominal_codes_on_centre_and_code  (cost_centre_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (cost_centre_id => reimbursements_cost_centres.id)
#
module Reimbursements
  ##
  # One line of a cost centre's chart of accounts. Owned by that centre alone
  # — a global list would let Fringe's admin retire a code Bedlam books
  # against, since the two centres are different EUSA accounts with their own
  # charts. code is a STRING and stays one: nominal codes are zero-padded
  # (041000), and an integer column would lose the padding at the source (see
  # Exports::Base#add_sheet, which pins every String cell to Axlsx :string
  # for the same reason).
  class NominalCode < ApplicationRecord
    include RecordId

    belongs_to :cost_centre, class_name: "Reimbursements::CostCentre"

    validates :code, :label, presence: true
    # case_sensitive: false because the column is utf8mb4_unicode_ci — the DB
    # index already folds case and accents, so a case-sensitive validation
    # would disagree with it and let a duplicate through to a RecordNotUnique.
    validates :code, uniqueness: { scope: :cost_centre_id, case_sensitive: false }

    scope :for_cost_centre, ->(cost_centre) { where(cost_centre: cost_centre).order(:code) }
  end
end
