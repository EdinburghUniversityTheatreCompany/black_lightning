# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Bank details submitted as raw params by the reimbursements portal
  # (PeopleController#save_bank_details, ExpenseEditsController#update_attrs) —
  # partial matching also covers sort_code_override/account_number_override.
  :sort_code, :account_number
]
