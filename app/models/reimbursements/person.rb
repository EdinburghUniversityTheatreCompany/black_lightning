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
  # A payee (registry of names and emails — not a user account). ActiveRecord
  # replacement for the Airtable-era PORO (now Reimbursements::Airtable::Person),
  # keeping its exact public interface so nothing above the Store changes.
  #
  # Bank details are NOT columns here — they live in the one-to-one
  # PaymentDetails record. The PORO exposed them flat, so the readers below
  # delegate and preserve the PORO's ""/false defaults for a payee without a
  # PaymentDetails row.
  class Person < ApplicationRecord
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
    # Case-insensitivity comes free from the MySQL *_ai_ci collation on the
    # unique index; this validation just gives a friendly error ahead of it.
    validates :email, uniqueness: { case_sensitive: false }, allow_nil: true

    # Blank emails are stored as NULL so the unique index permits many of them.
    def email=(value)
      super(value.presence)
    end

    def record_id = id&.to_s

    def sort_code = payment_details&.sort_code.to_s
    def account_number = payment_details&.account_number.to_s
    def notes = payment_details&.notes.to_s
    def verified = payment_details.present? && payment_details.verified
    alias verified? verified

    def bank_details?
      sort_code.present? && account_number.present?
    end
  end
end
