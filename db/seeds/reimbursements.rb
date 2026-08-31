# Reimbursements cost centres. Fringe (F40) is live; termtime (BED) becomes a
# second row when the portal takes over termtime payments.
#
# The notification role is who gets this centre's nightly operator reminders
# (Reimbursements::NotificationRecipients). It is required on the model, so it
# has to be seeded first or the cost centre save raises and takes the rest of
# the seed run down with it. Seeded EMPTY on purpose: a dev database has no
# business emailing anybody, and the Integration Status page badges the empty
# role so the gap is visible rather than silent.
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
