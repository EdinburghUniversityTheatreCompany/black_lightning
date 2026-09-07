# Reimbursements cost centres. Fringe (F40) is live; termtime (BED) becomes a
# second row when the portal takes over termtime payments.
#
# Nightly operator reminders go to the cost centre's own notification_email,
# falling back to this role (Reimbursements::NotificationRecipients). One of the
# two is required on the model, so the role has to be seeded first or the cost
# centre save raises and takes the rest of the seed run down with it. Seeded with
# an EMPTY role and no address on purpose: a dev database has no business
# emailing anybody, and the Integration Status page badges the gap so it is
# visible rather than silent.
notification_role = find_or_seed(Role, { name: "Fringe Finance Admin" })

find_or_seed(
  Reimbursements::CostCentre,
  { key: "fringe" },
  {
    name: "Bedlam Fringe 2026",
    eusa_code: "F40",
    receive_mailbox: "reimbursements@bedlamfringe.co.uk",
    send_mailbox: "reimbursements@bedlamfringe.co.uk",
    notification_role: notification_role
  }
)
seed_puts("Reimbursements cost centres seeded")
