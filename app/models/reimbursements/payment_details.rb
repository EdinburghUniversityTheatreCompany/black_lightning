# == Schema Information
#
# Table name: reimbursements_payment_details
# Database name: primary
#
#  id             :bigint           not null, primary key
#  account_number :string(255)      default(""), not null
#  bic            :string(255)      default(""), not null
#  iban           :string(255)      default(""), not null
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
  # A payee's bank details, one per Person. The notes column doubles as the
  # People page's audit trail.
  class PaymentDetails < ApplicationRecord
    include RecordId
    belongs_to :person, class_name: "Reimbursements::Person", inverse_of: :payment_details

    # Every writable column. The store's person-update path routes exactly these
    # keys here, so a field missing from the list is silently dropped; the FIELDS
    # test in payment_details_test.rb holds them in step.
    FIELDS = %i[sort_code account_number iban bic verified notes].freeze

    # Encrypted at rest, non-deterministic: nothing queries these by value.
    # `notes` is encrypted too because its audit trail can reference bank details.
    encrypts :sort_code
    encrypts :account_number
    encrypts :iban
    encrypts :bic
    encrypts :notes

    validates :person_id, uniqueness: true

    # validate_column_size is off (config/application.rb), so cap the plaintext
    # explicitly: string(255) holds ciphertext for ~123 characters. `notes` is TEXT
    # with ample headroom, so it is left uncapped.
    validates :sort_code, :account_number,
              length: { maximum: BankDetails::BANK_DIGITS_MAX_LENGTH }
    validates :iban, length: { maximum: BankDetails::IBAN_MAX_LENGTH }
    validates :bic, length: { maximum: BankDetails::BIC_MAX_LENGTH }

    # Appends one timestamped line to a notes trail. One formatter for both
    # callers (the People page and BankDetailsRetention) keeps the trail uniform.
    def self.append_note(existing, line, at: Time.current)
      stamped = "[#{at.utc.strftime('%Y-%m-%d %H:%M UTC')}] #{line}"
      existing.to_s.strip.empty? ? stamped : "#{existing.to_s.rstrip}\n#{stamped}"
    end
  end
end
