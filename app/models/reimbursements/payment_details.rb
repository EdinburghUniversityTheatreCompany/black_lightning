# == Schema Information
#
# Table name: reimbursements_payment_details
# Database name: primary
#
#  id             :bigint           not null, primary key
#  account_number :string(255)      default(""), not null
#  notes          :text(65535)
#  sort_code      :string(255)      default(""), not null
#  verified       :boolean          default(FALSE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  person_id      :bigint           not null
#
# Indexes
#
#  index_reimbursements_payment_details_on_person_id  (person_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (person_id => reimbursements_people.id)
#
module Reimbursements
  ##
  # A payee's bank details, split out of Person as a first-class model (one
  # per person today; unique index on person_id). The notes column doubles as
  # the People page's audit trail of verification decisions.
  class PaymentDetails < ApplicationRecord
    include RecordId
    belongs_to :person, class_name: "Reimbursements::Person", inverse_of: :payment_details

    validates :person_id, uniqueness: true

    def bank_details?
      sort_code.present? && account_number.present?
    end
  end
end
