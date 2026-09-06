##
# The international payment rail: paying a supplier abroad by IBAN instead of
# through UK BACS.
#
# payment_method is the discriminator rather than the currency, because the two
# come apart — an international supplier can invoice in GBP and still need an
# IBAN and EUSA's international form. Deriving the rail from the currency would
# bake in an assumption that breaks the first time that happens.
#
# amount / amount_excl_vat keep their existing meaning of GBP, so every budget
# rollup, expected_outturn, the over-budget check and reconcile are untouched.
# foreign_amount holds the figure that goes on EUSA's form (EUR today), and
# finance supplies the GBP equivalent at review.
class AddInternationalPaymentsToReimbursements < ActiveRecord::Migration[8.1]
  def change
    # A default means MySQL fills every existing row in the same statement, so
    # this needs no separate backfill step: every claim on file today was paid
    # through UK BACS, which is exactly what the default says.
    add_column :reimbursements_expenses, :payment_method, :string,
               default: "uk_bacs", null: false

    add_column :reimbursements_expenses, :foreign_amount, :decimal, precision: 12, scale: 2
    add_column :reimbursements_expenses, :foreign_currency, :string

    # Encrypted on the model, like the sort_code/account_number override pair
    # beside them. string(255) holds ciphertext for ~123 characters of
    # plaintext; an IBAN is at most 34 and a BIC 11.
    add_column :reimbursements_expenses, :iban_override, :string
    add_column :reimbursements_expenses, :bic_override, :string

    # Matching the sort_code / account_number convention on this table: NOT
    # NULL defaulting to "", so "no details on file" is one representation
    # rather than two.
    add_column :reimbursements_payment_details, :iban, :string, default: "", null: false
    add_column :reimbursements_payment_details, :bic, :string, default: "", null: false
  end
end
