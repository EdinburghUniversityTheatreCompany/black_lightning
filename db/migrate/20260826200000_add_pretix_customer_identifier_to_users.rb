class AddPretixCustomerIdentifierToUsers < ActiveRecord::Migration[8.1]
  # The pretix customer account this user signs into the ticket shop with.
  #
  # pretix keys an SSO account on a hash of the OIDC identity claim, and ours is
  # the email address, so the sync has had to match customers to users by email.
  # That is fragile in exactly the way it sounds: a member who changes their
  # website email gets a fresh, empty pretix account on their next login, and any
  # customer whose email never matched a user (12 of them today) can never be
  # matched at all. Switching the claim to the user id would fix it at the source
  # but is not available to us -- pretix refuses to let either identifier field be
  # rewritten on an SSO account, so every existing member would be locked out of
  # the shop. See docs/pretix/membership-sync.md.
  #
  # So the link is recorded on our side instead, the first time a customer is
  # matched by email. Afterwards that person is pinned by an opaque id and their
  # email can change freely. Same shape as Reimbursements::PersonLink, which
  # resolves a payee by its stored link first and by email only as a fallback.
  #
  # Nullable and blank for every existing row: it fills in as the reconcile meets
  # each customer, and a user who has never used the shop correctly has none.
  # Unique because one pretix customer is one person; the index also serves the
  # reconcile's lookup, which reads it once per run for every customer.
  def change
    add_column :users, :pretix_customer_identifier, :string, limit: 190
    add_index :users, :pretix_customer_identifier, unique: true
  end
end
