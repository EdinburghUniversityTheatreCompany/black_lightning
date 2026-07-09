module Reimbursements
  ##
  # A payee in the Airtable People table (registry of names, emails and bank
  # details — not a user account). PORO boundary type, mirroring bedlam-bacs.
  class Person
    attr_reader :record_id, :name, :email, :sort_code, :account_number, :verified, :notes

    def initialize(record_id:, name:, email:, sort_code: "", account_number: "", verified: false, notes: "")
      @record_id = record_id
      @name = name
      @email = email
      @sort_code = sort_code
      @account_number = account_number
      @verified = verified
      @notes = notes
    end

    def bank_details?
      sort_code.present? && account_number.present?
    end
  end
end
