# == Schema Information
#
# Table name: reimbursements_people
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  email              :string(255)
#  name               :string(255)      default(""), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  airtable_record_id :string(255)
#
# Indexes
#
#  index_reimbursements_people_on_airtable_record_id  (airtable_record_id) UNIQUE
#  index_reimbursements_people_on_email               (email) UNIQUE
#
module Reimbursements
  ##
  # A payee (not a user account). Bank details live in the one-to-one
  # PaymentDetails; the readers below answer ""/false with no row, so callers
  # never distinguish "no row" from "row with blanks".
  class Person < ApplicationRecord
    include RecordId
    has_many :expenses, class_name: "Reimbursements::Expense",
                        dependent: :nullify, inverse_of: :person
    has_one :payment_details, class_name: "Reimbursements::PaymentDetails",
                              dependent: :destroy, inverse_of: :person
    has_many :budget_ownerships, class_name: "Reimbursements::BudgetOwner",
                                 dependent: :destroy, inverse_of: :person
    has_many :owned_budgets, through: :budget_ownerships, source: :budget
    has_one :user, foreign_key: :reimbursements_person_id,
                   inverse_of: :reimbursements_person, dependent: :nullify

    validates :name, presence: true
    # Case-insensitivity comes from the column's collation (utf8mb4_unicode_ci) on
    # the unique index; this gives a friendly error ahead of it.
    validates :email, uniqueness: { case_sensitive: false }, allow_nil: true

    # Blank is stored as NULL so the unique index permits many.
    def email=(value)
      super(value.presence)
    end

    def sort_code = payment_details&.sort_code.to_s
    def account_number = payment_details&.account_number.to_s
    def iban = payment_details&.iban.to_s
    def bic = payment_details&.bic.to_s
    def notes = payment_details&.notes.to_s
    def verified = payment_details.present? && payment_details.verified
    alias verified? verified

    def bank_details?
      sort_code.present? && account_number.present?
    end

    # What to write when +actor+ saves this pair, or nil if it is the one already
    # stored. A change resets Verified (it only means something for the details
    # that were checked) and appends an audit line with BOTH values masked (as in
    # Exports::People): notes are encrypted at rest, but the visible copy must
    # stay masked too.
    def bank_details_change(new_sort_code, new_account_number, actor:)
      return if BankDetails.normalize_sort_code(new_sort_code) == BankDetails.normalize_sort_code(sort_code) &&
                BankDetails.normalize_account_number(new_account_number) == BankDetails.normalize_account_number(account_number)

      { sort_code: new_sort_code, account_number: new_account_number, verified: false,
        notes: PaymentDetails.append_note(
          notes,
          "Bank details updated: sort code #{BankDetails.mask(new_sort_code)}, " \
          "account #{BankDetails.mask(new_account_number)} by #{actor.name_or_email} (##{actor.id})"
        ) }
    end
  end
end
