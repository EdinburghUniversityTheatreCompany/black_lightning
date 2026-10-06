# Fringe (F40) is live; termtime (BED) becomes a second row when the portal takes over
# termtime payments. notification_email is required, and a dev database must not email
# anybody, so it is an undeliverable .invalid address (RFC 2606).
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
