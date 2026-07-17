class AddEndorsedAmountToReimbursementsOwnerEndorsements < ActiveRecord::Migration[8.1]
  def change
    # Snapshot of the claim's gross amount at sign-off. The gate is satisfied
    # only while the current claim still matches the endorsed budget AND amount,
    # so editing the amount or reassigning the budget after an endorsement
    # re-opens the gate — a prior sign-off can't become a blank cheque for
    # different terms. Nullable: a claim can be endorsed with no amount yet set.
    add_column :reimbursements_owner_endorsements, :endorsed_amount, :decimal, precision: 12, scale: 2
  end
end
