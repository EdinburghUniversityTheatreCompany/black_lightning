# Reimbursements cost centres. Fringe (F40) is live; termtime (BED) becomes a
# second row when the portal takes over termtime payments.
#
# Nightly operator reminders go to the cost centre's own notification_email
# (Reimbursements::NotificationRecipients), which is required on the model. A dev
# database has no business emailing anybody, so this is a deliberately
# undeliverable .invalid address (RFC 2606) rather than a real mailbox — and the
# outbound gate suppresses sends outside production anyway.
find_or_seed(
  Reimbursements::CostCentre,
  { key: "fringe" },
  {
    name: "Bedlam Fringe 2026",
    eusa_code: "F40",
    receive_mailbox: "reimbursements@bedlamfringe.co.uk",
    send_mailbox: "reimbursements@bedlamfringe.co.uk",
    notification_email: "finance@bedlamfringe.invalid"
  }
)
seed_puts("Reimbursements cost centres seeded")
