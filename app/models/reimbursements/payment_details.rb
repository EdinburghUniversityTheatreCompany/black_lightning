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

    # The operator-writable vocabulary, i.e. every column of this table that is not
    # bookkeeping. It lives here, next to the columns, because the store's person-update
    # path routes exactly these keys onto the payment_details record: keeping a second copy
    # over there meant a new bank field could be added to the model and then silently
    # dropped on the way in. `payment_details_fields_are_complete` in the model test holds
    # the two in step.
    FIELDS = %i[sort_code account_number verified notes].freeze

    # Bank details encrypted at rest. Non-deterministic (the default):
    # nothing queries these by value — the modulus check and the BACS builder
    # read the decrypted attributes, and uniqueness is on person_id. `notes`
    # is encrypted too because its audit trail can reference bank details.
    # support_unencrypted_data (config/application.rb) is on during the rollout
    # so pre-encryption plaintext rows keep reading until the backfill runs.
    encrypts :sort_code
    encrypts :account_number
    encrypts :notes

    validates :person_id, uniqueness: true

    # Column fit: Rails' auto-injected validate_column_size guard is off (it
    # measures the decrypted value — see config/application.rb), so cap the
    # plaintext explicitly instead. Both columns are string(255), which holds
    # ciphertext for roughly 123 characters of plaintext; a formatted UK sort code
    # or account number is 8. `notes` is TEXT (65535), with headroom for a far
    # longer audit trail than this app can produce, so it is left uncapped.
    validates :sort_code, :account_number,
              length: { maximum: BankDetails::BANK_DIGITS_MAX_LENGTH }

    def bank_details?
      sort_code.present? && account_number.present?
    end
  end
end
